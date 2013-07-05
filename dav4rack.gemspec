# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'dav4rack/version'

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

  s.files = `git ls-files`.split($/)
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  s.add_dependency 'nokogiri', '>= 1.4.2'
  s.add_dependency 'uuidtools', '~> 2.1.1'
  s.add_dependency 'rack', '>= 1.1.0'
end
