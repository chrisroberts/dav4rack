module RackDAV
  
  class Controller
    include RackDAV::HTTPStatus
    
    attr_reader :request, :response, :resource

    # request:: Rack::Request
    # response:: Rack::Response
    # options:: Options hash
    # Create a new Controller.
    # NOTE: options will be passed to Resource
    def initialize(request, response, options={})
      @request = request
      @response = response
      @options = options
      @resource = resource_class.new(actual_path, implied_path, @request, @options)
      authenticate
      raise Forbidden if request.path_info.include?('../')
    end
    
    # s:: string
    # Escape URL string
    def url_escape(s)
      s.gsub(/([^\/a-zA-Z0-9_.-]+)/n) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end.tr(' ', '+')
    end
    
    # s:: string
    # Unescape URL string
    def url_unescape(s)
      s.tr('+', ' ').gsub(/((?:%[0-9a-fA-F]{2})+)/n) do
        [$1.delete('%')].pack('H*')
      end
    end  
    
    # Return response to OPTIONS
    def options
      response["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
      response["Dav"] = "2"
      response["Ms-Author-Via"] = "DAV"
      NoContent
    end
    
    # Return response to HEAD
    def head
      raise NotFound unless resource.exist?
      response['Etag'] = resource.etag
      response['Content-Type'] = resource.content_type
      response['Last-Modified'] = resource.last_modified.httpdate
      NoContent
    end
    
    # Return response to GET
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

    # Return response to PUT
    def put
      raise Forbidden if resource.collection?
      resource.put(request, response)
    end

    # Return response to POST
    def post
      resource.post(request, response)
    end

    # Return response to DELETE
    def delete
      raise NotFound unless resource.exist?
      resource.delete
    end
    
    # Return response to MKCOL
    def mkcol
      resource.make_collection
    end
    
    # Return response to COPY
    def copy
      move(:copy)
    end

    # args:: Only argument used: :copy
    # Move Resource to new location. If :copy is provided,
    # Resource will be copied (implementation ease)
    def move(*args)
      raise NotFound unless resource.exist?
      dest_uri = URI.parse(env['HTTP_DESTINATION'])
      destination = url_unescape(dest_uri.path)
      raise BadGateway if dest_uri.host and dest_uri.host != request.host
      raise Forbidden if destination == resource.public_path
      dest = resource_class.new(destination, clean_path(destination), @request, @options)
      if(args.include?(:copy))
        resource.copy(dest, overwrite)
      else
        raise Conflict unless depth.is_a?(Symbol) || depth > 1
        resource.move(dest)
      end
    end
    
    # Return respoonse to PROPFIND
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
          xml.response do
            xml.href "#{scheme}://#{host}:#{port}#{url_escape(resource.public_path)}"
            propstats(xml, get_properties(resource, names))
          end
        end
      end
    end
    
    # Return response to PROPPATCH
    def proppatch
      raise NotFound unless resource.exist?
      prop_rem = request_match('/propertyupdate/remove/prop').children.map{|n| [n.name] }
      prop_set = request_match('/propertyupdate/set/prop').children.map{|n| [n.name, n.text] }
      multistatus do |xml|
        find_resources.each do |resource|
          xml.response do
            xml.href "#{scheme}://#{host}:#{port}#{url_escape(resource.public_path)}"
            propstats(xml, set_properties(resource, prop_set))
          end
        end
      end
    end


    # Lock current resource
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
          xml.lockdiscovery do
            xml.activelock do
              if(asked[:scope])
                xml.lockscope do
                  xml.send(asked[:scope])
                end
              end
              if(asked[:type])
                xml.locktype do
                  xml.send(asked[:type])
                end
              end
              xml.depth asked[:depth].to_s
              xml.timeout lock_time ? "Second-#{lock_time}" : 'infinity'
              xml.locktoken do
                xml.href locktoken
              end
            end
          end
        end
        response.status = resource.exist? ? OK : Created
      rescue LockFailure => e
        multistatus do |xml|
          e.path_status.each_pair do |path, status|
            xml.response do
              xml.href path
              xml.status "#{http_version} #{status.status_line}"
            end
          end
        end
        response.status = MultiStatus
      end
    end

    # Unlock current resource
    def unlock
      resource.unlock(lock_token)
    end

    # ************************************************************
    # private methods
    
    private

    # Request environment variables
    def env
      @request.env
    end
    
    # Current request scheme (http/https)
    def scheme
      request.scheme
    end
    
    # Request host
    def host
      request.host
    end
    
    # Request port
    def port
      request.port
    end
    
    # Class of the resource in use
    def resource_class
      @options[:resource_class]
    end

    # Root URI path for the resource
    def root_uri_path
      @options[:root_uri_path]
    end
    
    # Returns Resource path with root URI removed
    def implied_path
      clean_path(@request.path.dup)
    end
    
    # x:: request path
    # Unescapes path and removes root URI if applicable
    def clean_path(x)
      ip = url_unescape(x)
      ip.gsub!(/^#{Regexp.escape(root_uri_path)}/, '') if root_uri_path
      ip
    end
    
    # Unescaped request path
    def actual_path
      url_unescape(@request.path.dup)
    end

    # Lock token if provided by client
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

    # Current HTTP version being used
    def http_version
      env['HTTP_VERSION'] || env['SERVER_PROTOCOL'] || 'HTTP/1.0'
    end
    
    # Overwrite is allowed
    def overwrite
      env['HTTP_OVERWRITE'].to_s.upcase != 'F'
    end

    # Find resources at depth requested
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
    
    # XML parsed request
    def request_document
      @request_document ||= Nokogiri.XML(request.body.read)
    rescue
      raise BadRequest
    end

    # Namespace being used within XML document
    # TODO: Make this better
    def ns
      _ns = ''
      if(request_document && request_document.root && request_document.root.namespace_definitions.size > 0)
        _ns = request_document.root.namespace_definitions.first.prefix.to_s
        _ns += ':' unless _ns.empty?
      end
      _ns
    end
    
    # pattern:: XPath pattern
    # Search XML document for given XPath
    def request_match(pattern)
      nil unless request_document
      request_document.xpath(pattern, request_document.root.namespaces)
    end

    # root_type:: Root tag name
    # Render XML and set Rack::Response#body= to final XML
    def render_xml(root_type)
      raise ArgumentError.new 'Expecting block' unless block_given?
      doc = Nokogiri::XML::Builder.new do |xml|
        xml.send(root_type.to_s, 'xmlns' => 'DAV:') do
#           xml.parent.namespace = xml.parent.namespace_definitions.first
          yield xml
        end
      end
      
      response.body = doc.to_xml
      response["Content-Type"] = 'text/xml; charset="utf-8"'
      response["Content-Length"] = response.body.size.to_s
    end
      
    # block:: block
    # Creates a multistatus response using #render_xml and
    # returns the correct status
    def multistatus(&block)
      render_xml(:multistatus, &block)
      MultiStatus
    end
    
    # xml:: Nokogiri::XML::Builder
    # errors:: Array of errors
    # Crafts responses for errors
    def response_errors(xml, errors)
      for path, status in errors
        xml.response do
          xml.href "#{scheme}://#{host}:#{port}#{path}"
          xml.status "#{http_version} #{status.status_line}"
        end
      end
    end

    # resource:: Resource
    # names:: Property names
    # Returns array of property values for given names
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

    # resource:: Resource
    # pairs:: name value pairs
    # Sets the given properties
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
    
    # xml:: Nokogiri::XML::Builder
    # stats:: Array of stats
    # Build propstats response
    def propstats(xml, stats)
      return if stats.empty?
      for status, props in stats
        xml.propstat do
          xml.prop do
            for name, value in props
              if(value.is_a?(Nokogiri::XML::Node))
                xml.send(name) do
                  xml_convert(xml, value)
                end
              elsif(value.is_a?(Symbol))
                xml.send(name) do
                  xml.send(value)
                end
              else
                xml.send(name, value)
              end
            end
          end
          xml.status "#{http_version} #{status.status_line}"
        end
      end
    end
    
    # xml:: Nokogiri::XML::Builder
    # element:: Nokogiri::XML::Element
    # Converts element into proper text
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

    # Perform authentication
    # NOTE: Authentication will only be performed if the Resource
    # has defined an #authenticate method
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
        response['WWW-Authenticate'] = "Basic realm=\"#{resource.respond_to?(:authentication_realm) ? resource.authentication_realm : 'Locked content'}\""
        raise Unauthorized.new unless authed
      end
    end

  end

end 
