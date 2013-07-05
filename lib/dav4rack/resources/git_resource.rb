require 'grit'
require 'logger'

module DAV4Rack

  # Read-only resource on top of a bare Git repository
  # Initialize with a git (bare or clone) directory:
  # DAV4Rack::Handler.new(:git_dir => 'path/to/repo.git', :resource_class => ::DAV4Rack::GitResource, :root_uri_path => '')
  class GitResource < Resource

    def children
      git_object.contents.map do |obj|
        child(obj.name)
      end
    end

    def collection?
      git_object.is_a?(Grit::Tree)
    end

    def exist?
      git_object != nil
    end

    def creation_date
      repo.log('HEAD', relative_path).last.date rescue Time.at(0)
    end

    def last_modified
      repo.log('HEAD', relative_path, max_count: 1).first.date rescue Time.at(0)
    end

    def etag
      git_object.id
    end

    def content_type
      git_object.mime_type
    end

    def content_length
      git_object.size rescue 0
    end

    def get(request, response)
      raise NotFound unless exist?
      response.body = git_object.data
      OK
    end

    #
    # Read Only Implementation, so we dissallow the following requests
    #
    def forbidden(*args)
      raise HTTPStatus::Forbidden
    end

    %w{put post delete copy move make_collection lock unlock}.each { |method| alias_method method, :forbidden }

    private
    def git_dir
      @options[:git_dir]
    end

    def repo
      @repo ||= Grit::Repo.new(git_dir)
    end

    def git_object
      @git_object ||= fetch_git_object
    end

    # Returns the git object at given path
    def fetch_git_object
      return repo.tree if relative_path == ""
      repo.tree / relative_path
    end

    def relative_path
      path.gsub(/^\//,'')
    end

  end

end
