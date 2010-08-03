Gem::Specification.new do |s|
  s.name = 'dav4rack'
  s.version = '0.0.1'
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Chris Roberts'
  s.email = 'chris@chrisroberts.org'
  s.homepage = 'http://github.com/dav4rack'
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
bin/dav4rack
spec/handler_spec.rb
README.rdoc
}
end
