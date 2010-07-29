module RackDAV
  
  class Controller
    include RackDAV::HTTPStatus
    
    attr_reader :request, :response, :resource
    
    def initialize(request, response, options)
      @request = request
      @response = response
      @options = options
      @resource = resource_class.new(request.env['REQUEST_PATH'], implied_path, @options)
      authenticate
      raise Forbidden if request.path_info.include?('../')
    end
    
    def url_escape(s)
      URI.escape(s)
    end

    def url_unescape(s)
      URI.unescape(s)
    end    
    
    def options
      response["Allow"] = 'OPTIONS,HEAD,GET,PUT,POST,DELETE,PROPFIND,PROPPATCH,MKCOL,COPY,MOVE,LOCK,UNLOCK'
      response["Dav"] = "2"
      response["Ms-Author-Via"] = "DAV"
    end
    
    def head
      raise NotFound unless resource.exist?
      response['Etag'] = resource.etag
      response['Content-Type'] = resource.content_type
      response['Last-Modified'] = resource.last_modified.httpdate
    end
    
    def get
      raise NotFound unless resource.exist?
      map_exceptions do
        resource.get(request, response)
      end
      if(response.status == 200 && !resource.collection?)
        response['Etag'] = resource.etag
        response['Content-Type'] = resource.content_type
        response['Content-Length'] = resource.content_length.to_s
        response['Last-Modified'] = resource.last_modified.httpdate
      end
      response
    end

    def put
      raise Forbidden if resource.collection?
      map_exceptions do
        resource.put(request, response)
      end
    end

    def post
      map_exceptions do
        resource.post(request, response)
      end
    end

    def delete
      raise NotFound unless resource.exist?
      map_exceptions do
        resource.delete
      end
      response.status = OK
    end
    
    def mkcol
      map_exceptions do
        resource.make_collection
      end
      response.status = Created
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
        raise Conflict if depth <= 1
        resource.move(dest)
      end
    end
    
    def propfind
      raise NotFound unless resource.exist?
      unless(request_match('/propfind/allprop').empty?)
        names = resource.property_names
      else
        names = request_match('/propfind/prop').children.map{|n|n.name}
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
      resource.save
    end

    # TODO: Rewrite this to actually do something useful
    # NOTE: Providing real locking the the resource is allowed to 
    # handle will provide an easy way to deal with all the dot files
    # os x throws at the system
    def lock
      raise NotFound unless resource.exist?

      lockscope = request_match('/lockinfo/lockscope').first.name
      locktype = request_match('/lockinfo/locktype').first.name
      owner = request_match('/lockinfo/owner/href').first
      locktoken = "opaquelocktoken:" + sprintf('%x-%x-%s', Time.now.to_i, Time.now.sec, resource.etag)

      response['Lock-Token'] = locktoken

      render_xml(:prop) do |xml|
        xml['D'].lockdiscovery do
          xml['D'].activelock do
            xml['D'].lockscope lockscope
            xml['D'].locktype locktype
            xml['D'].depth 'Infinity'
            if owner
              xml['D'].owner { xml['D'].href owner.text }
            end
            xml['D'].timeout "Second-60"
            xml['D'].locktoken do
              xml['D'].href locktoken
            end
          end
        end
      end
    end

    # TODO: Rewrite this to actually do something useful
    def unlock
      raise NoContent
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
      clean_path(@request.path_info.dup)
    end
    
    def clean_path(x)
      ip = url_unescape(x)
      ip.gsub!(/^#{Regexp.escape(root_uri_path)}/, '') if root_uri_path
      ip
    end
    
    def actual_path
      url_unescape(@request.path_info)
    end
    
    def depth
      case env['HTTP_DEPTH']
      when '0' then 0
      when '1' then 1
      else 100
      end
    end

    def overwrite
      env['HTTP_OVERWRITE'].to_s.upcase != 'F'
    end

    # TODO: Adding current resource causes weird duplication when using
    # a webdav path. Test this method when using root path. If original is
    # needed, we can simply check if the path is set or not and include
    # current if needed
    def find_resources
      ary = nil
      case env['HTTP_DEPTH']
      when '0'
        # [resource]
        ary = [resource]
      when '1'
        # [resource] + resource.children
        ary = resource.children
      else
        # [resource] + resource.descendants
        ary = resource.descendants
      end
      ary ? ary : []
    end
    
    def map_exceptions
      yield
    rescue
      case $!
      when URI::InvalidURIError then raise BadRequest
      when Errno::EACCES then raise Forbidden
      when Errno::ENOENT then raise Conflict
      when Errno::EEXIST then raise Conflict      
      when Errno::ENOSPC then raise InsufficientStorage
      else
        raise
      end
    end
    
    def request_document
      @request_document ||= Nokogiri.XML(request.body.read)
    rescue REXML::ParseException
      raise BadRequest
    end

    def request_match(pattern)
      request_document.xpath(pattern, '' => 'DAV:')
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
      response.status = MultiStatus
    end
    
    def response_errors(xml, errors)
      for path, status in errors
        xml['D'].response do
          xml['D'].href "#{scheme}://#{host}:#{port}#{path}"
          xml['D'].status "#{request.env['HTTP_VERSION']} #{status.status_line}"
        end
      end
    end

    def get_properties(resource, names)
      stats = Hash.new { |h, k| h[k] = [] }
      for name in names
        begin
          map_exceptions do
            stats[OK] << [name, resource.get_property(name)]
          end
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
          map_exceptions do
            stats[OK] << [name, resource.set_property(name, value)]
          end
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
          xml['D'].status "#{request.env['HTTP_VERSION']} #{status.status_line}"
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
