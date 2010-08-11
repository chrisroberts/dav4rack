require 'dav4rack/interceptor_resource'
module DAV4Rack
  class Interceptor
    def initialize(app, args={})
      @roots = args[:mappings].keys
      @args = args
      @app = app
    end

    def call(env)
      path = env['PATH_INFO'].downcase
      method = env['REQUEST_METHOD'].upcase
      app = nil
      if(@roots.detect{|x| path =~ /^#{Regexp.escape(x.downcase)}\/?/}.nil? && %w(OPTIONS PUT PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK).include?(method))
        app = DAV4Rack::Handler.new(:resource_class => InterceptorResource, :mappings => @args[:mappings], :log_to => @args[:log_to])
      end
      app ? app.call(env) : @app.call(env)
    end
  end
end