require 'rack_dav/interceptor_resource'
module RackDAV
  class Interceptor
    def initialize(app, args={})
      @roots = args[:handlers].keys
      @args = args
      @app = app
    end
    
    def call(env)
      path = env['REQUEST_PATH'].downcase
      method = env['REQUEST_METHOD']
      if(@roots.detect{|x| path =~ /^#{Regexp.escape(x.downcase)}\/?/}.nil? && ['OPTIONS', 'PROPFIND'].include?(method))
        @app = RackDAV::Handler.new(:resource_class => InterceptorResource, :handlers => @args[:handlers])
      end
      @app.call(env)
    end
  end
end