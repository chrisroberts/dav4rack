module RackDAV
  
  class Controller
    include RackDAV::HTTPStatus
    
    attr_reader :request, :response, :resource
    
    def initialize(request, response, options)
      @request = request
      @response = response
      @options = options
      @resource = resource_class.new(actual_path, implied_path, @request, @options)
      authenticate
      raise Forbidden if request.path_info.include?('../')
    end
    
    
    def url_escape(s)
      s.gsub(/([^\/a-zA-Z0-9_.-]+)/n) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end.tr(' ', '+')
    end
    
    def url_unescape(s)
      s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) do
        [$1.delete('%')].pack('H*')
      end
    end  
    
    def options
      response["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
      response["Dav"] = "2"
      response["Ms-Author-Via"] = "DAV"
      NoContent
    end
    
    def head
      raise NotFound unless resource.exist?
      response['Etag'] = resource.etag
      response['Content-Type'] = resource.content_type
      response['Last-Modified'] = resource.last_modified.httpdate
      NoContent
    end
    
    def get
      raise NotFound unless resource.exist?
      res = resource.get(request, response)
      if(response.status == 200 && !resource.collection?)
        response['Etag'] = resource.etag
        response['Content-Type'] = resource.content_type
        response['Content-Length'] = resource.content_length.to_s
        response['Last-Modified'] = resource.last_modified.httpdate
      end
      res
    end

    def put
      raise Forbidden if resource.collection?
      resource.put(request, response)
    end

    def post
      resource.post(request, response)
    end

    def delete
      raise NotFound unless resource.exist?
      resource.delete
    end
    
    def mkcol
      resource.make_collection
    end
    
    def copy
      move(:copy)
    end

    def move(*args)
      raise NotFound unless resource.exist?
      dest_uri = URI.parse(env['HTTP_DESTINATION'])
      destination = url_unescape(dest_uri.path)
      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.public_path
      dest = resource_class.new(destination, clean_path(destination), @options)
      if(args.include?(:copy))
        resource.copy(dest, overwrite)
      else
        raise Conflict unless depth.is_a?(Symbol) || depth > 1
        resource.move(dest)
      end
    end
    
    def propfind
      raise NotFound unless resource.exist?
      unless(request_document.xpath("//#{ns}propfind/#{ns}allprop").empty?)
        names = resource.property_names
      else
        names = request_document.xpath("//#{ns}propfind/#{ns}prop").children.find_all{|n|n.element?}.map{|n|n.name}
        names = resource.property_names if names.empty?
      end
      multistatus do |xml|
        find_resources.each do |resource|
          xml['D'].response do
            xml['D'].href "#{scheme}://#{host}:#{port}#{url_escape(resource.public_path)}"
            propstats(xml, get_properties(resource, names))
          end
        end
      end
    end
    
    def proppatch
      raise NotFound unless resource.exist?
      prop_rem = request_match('/propertyupdate/remove/prop').children.map{|n| [n.name] }
      prop_set = request_match('/propertyupdate/set/prop').children.map{|n| [n.name, n.text] }
      multistatus do |xml|
        find_resources.each do |resource|
          xml['D'].response do
            xml['D'].href "#{scheme}://#{host}:#{port}#{url_escape(resource.public_path)}"
            propstats(xml, set_properties(resource, prop_set))
          end
        end
      end
    end


    # Locks a resource
    # NOTE: This will pass an argument hash to Resource#lock and
    # wait for a success/failure response. 
    def lock
      raise NotFound unless resource.exist?
      lockinfo = request_document.xpath("//#{ns}lockinfo")
      asked = {}
      asked[:timeout] = request.env['Timeout'].split(',').map{|x|x.strip} if request.env['Timeout']
      asked[:depth] = depth
      raise BadRequest unless [0, :infinity].include?(asked[:depth])
      asked[:scope] = lockinfo.xpath("//#{ns}lockscope").children.find_all{|n|n.element?}.map{|n|n.name}.first
      asked[:type] = lockinfo.xpath("#{ns}locktype").children.find_all{|n|n.element?}.map{|n|n.name}.first
      asked[:owner] = lockinfo.xpath("//#{ns}owner/#{ns}href").children.map{|n|n.text}.first
      begin
        lock_time, locktoken = resource.lock(asked)
        render_xml(:prop) do |xml|
          xml['D'].lockdiscovery do
            xml['D'].activelock do
              if(asked[:scope])
                xml['D'].lockscope do
                  xml['D'].send(asked[:scope])
                end
              end
              if(asked[:type])
                xml['D'].locktype do
                  xml['D'].send(asked[:type])
                end
              end
              xml['D'].depth asked[:depth].to_s
              xml['D'].timeout lock_time ? "Second-#{lock_time}" : 'infinity'
              xml['D'].locktoken do
                xml['D'].href locktoken
              end
            end
          end
        end
        response.status = resource.exist? ? OK : Created
      rescue LockFailure => e
        multistatus do |xml|
          e.path_status.each_pair do |path, status|
            xml['D'].response do
              xml['D'].href path
              xml['D'].status "#{http_version} #{status.status_line}"
            end
          end
        end
        response.status = MultiStatus
      end
    end

    def unlock
      resource.unlock(lock_token)
    end

    # ************************************************************
    # private methods
    
    private

    def env
      @request.env
    end
    
    def scheme
      request.scheme
    end
    
    def host
      request.host
    end
    
    def port
      request.port
    end
    
    def resource_class
      @options[:resource_class]
    end

    def root_uri_path
      @options[:root_uri_path]
    end
    
    def implied_path
      clean_path(@request.path.dup)
    end
    
    def clean_path(x)
      ip = url_unescape(x)
      ip.gsub!(/^#{Regexp.escape(root_uri_path)}/, '') if root_uri_path
      ip
    end
    
    def actual_path
      url_unescape(@request.path.dup)
    end

    def lock_token
      env['HTTP_LOCK_TOKEN'] || nil
    end
    
    # Requested depth
    def depth
      d = env['HTTP_DEPTH']
      if(d =~ /^\d+$/)
        d = d.to_i
      else
        d = :infinity
      end
      d
    end

    def http_version
      env['HTTP_VERSION'] || env['SERVER_PROTOCOL'] || 'HTTP/1.0'
    end
    
    # Overwrite is allowed
    def overwrite
      env['HTTP_OVERWRITE'].to_s.upcase != 'F'
    end

    # TODO: Adding current resource causes weird duplication when using
    # a webdav path. Test this method when using root path. If original is
    # needed, we can simply check if the path is set or not and include
    # current if needed
    def find_resources
      ary = nil
      case depth
      when 0
        ary = [resource]
      when 1
        ary = resource.children
      else
        ary = resource.descendants
      end
      ary ? ary : []
    end
    
    def request_document
      @request_document ||= Nokogiri.XML(request.body.read)
    rescue
      raise BadRequest
    end

    def ns
      _ns = ''
      if(request_document && request_document.root && request_document.root.namespace_definitions.size > 0)
        _ns = request_document.root.namespace_definitions.first.prefix.to_s
        _ns += ':' unless _ns.empty?
      end
      _ns
    end
    
    def request_match(pattern)
      nil unless request_document
      request_document.xpath(pattern, request_document.root.namespaces)
    end

    def render_xml(root_type)
      raise ArgumentError.new 'Expecting block' unless block_given?
      doc = Nokogiri::XML::Builder.new do |xml|
        xml.send(root_type.to_s, 'xmlns:D' => 'DAV:') do
          xml.parent.namespace = xml.parent.namespace_definitions.first
          yield xml
        end
      end
      
      response.body = doc.to_xml
      response["Content-Type"] = 'text/xml; charset="utf-8"'
      response["Content-Length"] = response.body.size.to_s
    end
      
    def multistatus(&block)
      render_xml(:multistatus, &block)
      MultiStatus
    end
    
    def response_errors(xml, errors)
      for path, status in errors
        xml['D'].response do
          xml['D'].href "#{scheme}://#{host}:#{port}#{path}"
          xml['D'].status "#{http_version} #{status.status_line}"
        end
      end
    end

    def get_properties(resource, names)
      stats = Hash.new { |h, k| h[k] = [] }
      for name in names
        begin
          val = resource.get_property(name)
          stats[OK].push [name, val] if val
        rescue Status
          stats[$!] << name
        end
      end
      stats
    end

    def set_properties(resource, pairs)
      stats = Hash.new { |h, k| h[k] = [] }
      for name, value in pairs
        begin
          stats[OK] << [name, resource.set_property(name, value)]
        rescue Status
          stats[$!] << name
        end
      end
      stats
    end
    
    def propstats(xml, stats)
      return if stats.empty?
      for status, props in stats
        xml['D'].propstat do
          xml['D'].prop do
            for name, value in props
              if(value.is_a?(Nokogiri::XML::Node))
                xml['D'].send(name) do
                  xml_convert(xml, value)
                end
              elsif(value.is_a?(Symbol))
                xml['D'].send(name) do
                  xml['D'].send(value)
                end
              else
                xml['D'].send(name, value)
              end
            end
          end
          xml['D'].status "#{http_version} #{status.status_line}"
        end
      end
    end
    
    def xml_convert(xml, element)
      if element.children.empty?
        if element.text?
          xml.send(element.name, element.text, element.attributes)
        else
          xml.send(element.name, element.attributes)
        end
      else
        xml.send(element.name, element.attributes) do
          element.elements.each do |child|
            xml_convert(xml, child)
          end
        end
      end
    end

    def authenticate
      authed = true
      if(resource.respond_to?(:authenticate))
        authed = false
        if(request.env['HTTP_AUTHORIZATION'])
          auth = Rack::Auth::Basic::Request.new(request.env)
          if(auth.basic? && auth.credentials)
            authed = resource.authenticate(auth.credentials[0], auth.credentials[1])
          end
        end
      end
      unless(authed)
        response.body = resource.respond_to?(:authentication_error_msg) ? resource.authentication_error_msg : 'Not Authorized'
        response['Content-Length'] = response.body.length
        response['WWW-Authenticate'] = "Basic realm=\"#{resource.respond_to?(:authentication_realm) ? resource.authentication_realm : 'Locked content'}\""
        raise Unauthorized.new unless authed
      end
    end

  end

end 
