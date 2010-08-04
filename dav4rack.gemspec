require 'dav4rack'
Gem::Specification.new do |s|
  s.name = 'dav4rack'
  s.version = DAV4Rack::VERSION
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Chris Roberts'
  s.email = 'chrisroberts.code@gmail.com'
  s.homepage = 'http://github.com/chrisroberts/dav4rack'
  s.description = 'WebDAV handler for Rack'
  s.require_path = 'lib'
  s.executables << 'dav4rack'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.rdoc']  
  s.files = %w{
.gitignore
LICENSE
dav4rack.gemspec
lib/dav4rack.rb
lib/dav4rack/file_resource.rb
lib/dav4rack/handler.rb
lib/dav4rack/controller.rb
lib/dav4rack/http_status.rb
lib/dav4rack/resource.rb
lib/dav4rack/interceptor.rb
lib/dav4rack/interceptor_resource.rb
lib/dav4rack/remote_file.rb
lib/dav4rack/lock.rb
lib/dav4rack/lock_store.rb
bin/dav4rack
spec/handler_spec.rb
README.rdoc
}
end
