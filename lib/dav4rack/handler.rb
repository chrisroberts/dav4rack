module DAV4Rack
  
  class Handler
    include DAV4Rack::HTTPStatus    
    def initialize(options={})
      @options = options.dup
      unless(@options[:resource_class])
        require 'dav4rack/file_resource'
        @options[:resource_class] = FileResource
        @options[:root] ||= Dir.pwd
      end
    end

    def call(env)
      
      request = Rack::Request.new(env)
      response = Rack::Response.new

      controller = nil
      begin
        controller = Controller.new(request, response, @options.dup)
        controller.authenticate
        res = controller.send(request.request_method.downcase)
        response.status = res.code if res.respond_to?(:code)
      rescue HTTPStatus::Unauthorized => status
        response.body = controller.resource.respond_to?(:authentication_error_msg) ? controller.resource.authentication_error_msg : 'Not Authorized'
        response['WWW-Authenticate'] = "Basic realm=\"#{controller.resource.respond_to?(:authentication_realm) ? controller.resource.authentication_realm : 'Locked content'}\""
        response.status = status.code
      rescue HTTPStatus::Status => status
        response.status = status.code
      end

      # Strings in Ruby 1.9 are no longer enumerable.  Rack still expects the response.body to be
      # enumerable, however.
      
      response['Content-Length'] = response.body.to_s.length unless response['Content-Length'] || !response.body.is_a?(String)
      response.body = [response.body] if not response.body.respond_to? :each
      response.status = response.status ? response.status.to_i : 200
      response.headers.each_pair{|k,v| response[k] = v.to_s}
      
      # Apache wants the body dealt with, so just read it and junk it
      buf = true
      buf = request.body.read(8192) while buf

      response.finish
    end
    
  end

end
