module RackDAV
  
  class Handler
    include RackDAV::HTTPStatus    
    def initialize(options={})
      @options = options.dup
      unless(@options[:resource_class])
        require 'file_resource'
        @options[:resource_class] = FileResource
        @options[:root] = Dir.pwd
      end
    end

    def call(env)

      request = Rack::Request.new(env)
      response = Rack::Response.new
      
      begin
        controller = Controller.new(request, response, @options.dup)
        res = controller.send(request.request_method.downcase)
        response.status = res.code if res.respond_to?(:code)
      rescue HTTPStatus::Status => status
        response.status = status.code
      end

      # Strings in Ruby 1.9 are no longer enumerable.  Rack still expects the response.body to be
      # enumerable, however.

      response.body = [response.body] if not response.body.respond_to? :each
      response.status = response.status ? response.status.to_i : 200
      response['Content-Length'] = response.body.to_s.length unless response['Content-Length']
      response.headers.each_pair{|k,v| response[k] = v.to_s}

      # Apache wants the body dealt with, so just read it and junk it
      buf = true
      buf = request.body.read(8192) while buf
      
      response.finish
    end
    
  end

end
