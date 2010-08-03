Gem::Specification.new do |s|
  s.name = 'rack_dav'
  s.version = '0.1.1'
  s.summary = 'WebDAV handler for Rack'
  s.author = 'Matthias Georgi'
  s.email = 'matti.georgi@gmail.com'
  s.homepage = 'http://www.matthias-georgi.de/rack_dav'
  s.description = 'WebDAV handler for Rack'
  s.require_path = 'lib'
  s.executables << 'rack_dav'
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.md']  
  s.files = %w{
.gitignore
LICENSE
rack_dav.gemspec
lib/rack_dav.rb
lib/rack_dav/file_resource.rb
lib/rack_dav/handler.rb
lib/rack_dav/controller.rb
lib/rack_dav/http_status.rb
lib/rack_dav/resource.rb
lib/rack_dav/interceptor.rb
lib/rack_dav/interceptor_resource.rb
lib/rack_dav/remote_file.rb
bin/rack_dav
spec/handler_spec.rb
README.md
}
end
