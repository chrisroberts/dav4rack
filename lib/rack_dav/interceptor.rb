require 'rack_dav/interceptor_resource'
module RackDAV
  class Interceptor
    def initialize(app, args={})
      @roots = args[:mappings].keys
      @args = args
      @app = app
    end

    def call(env)
      path = env['REQUEST_PATH'].downcase
      method = env['REQUEST_METHOD']
      app = nil
      if(@roots.detect{|x| path =~ /^#{Regexp.escape(x.downcase)}\/?/}.nil? && %w(OPTIONS PUT PROPFIND PROPPATCH MKCOL COPY MOVE LOCK UNLOCK).include?(method))
        puts "Intercepting with method: #{method} for path: #{path}"
        app = RackDAV::Handler.new(:resource_class => InterceptorResource, :mappings => @args[:mappings])
      end
      app ? app.call(env) : @app.call(env)
    end
  end
end