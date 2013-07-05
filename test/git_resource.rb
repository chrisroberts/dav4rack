$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../lib'))

require 'rubygems'
require 'dav4rack'
require 'dav4rack/resources/git_resource'
require 'rack/test'
require 'test/unit'

class GitResource < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    git_dir = File.expand_path(File.dirname(__FILE__) + '/fixtures/smallgit.git')
    DAV4Rack::Handler.new(:git_dir => git_dir, :resource_class => ::DAV4Rack::GitResource, :root_uri_path => '')
  end

  def test_get_file
    get '/readme'
    assert_equal "This is a super simple test git repo\nIt contains a file and directory\n", last_response.body
  end

  def test_get_nested_file
    get '/testdir/date'
    assert_equal "Fri Jul  5 10:59:13 CEST 2013\n", last_response.body
  end

  def test_nonexisting_file
    get '/does/not/exist'
    assert_equal 404, last_response.status
  end
end