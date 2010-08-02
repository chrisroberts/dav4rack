module RackDAV
  
  class LockFailure < RuntimeError
    attr_reader :path_status
    def initialize(*args)
      super(*args)
      @path_status = {}
    end
    
    def add_failure(path, status)
      @path_status[path] = status
    end
  end
  
  class Resource
    attr_reader :path, :options, :public_path
    
    include RackDAV::HTTPStatus
    
    def initialize(public_path, path, options)
      @public_path = public_path.dup
      @path = path.dup
      @options = options.dup
    end
        
    # If this is a collection, return the child resources.
    def children
      raise NotImplementedError
    end

    # Is this resource a collection?
    def collection?
      raise NotImplementedError
    end

    # Does this recource exist?
    def exist?
      raise NotImplementedError
    end
    
    # Return the creation time.
    def creation_date
      raise NotImplementedError
    end

    # Return the time of last modification.
    def last_modified
      raise NotImplementedError
    end
    
    # Set the time of last modification.
    def last_modified=(time)
      raise NotImplementedError
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      raise NotImplementedError
    end

    # Return the resource type.
    def resource_type
      :collection if collection?
    end

    # Return the mime type of this resource.
    def content_type
      raise NotImplementedError
    end

    # Return the size in bytes for this resource.
    def content_length
      raise NotImplementedError
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      raise NotImplementedError
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      raise NotImplementedError
    end
    
    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise NotImplementedError
    end
    
    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      raise NotImplementedError
    end
    
    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest)
      raise NotImplementedError
    end
  
    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest)
      copy(dest)
      delete
    end
    
    # args:: Hash of lock arguments
    # Request for a lock on the given resource. A valid lock should lock
    # all descendents. Failures should be noted and returned as an exception
    # using LockFailure.
    # Valid args keys: :timeout -> requested timeout
    #                  :depth -> lock depth
    #                  :scope -> lock scope
    #                  :type -> lock type
    #                  :owner -> lock owner
    # Should return a tuple: [lock_time, locktoken] where lock_time is the
    # given timeout
    # NOTE: See section 9.10 of RFC 4918 for guidance about
    # how locks should be generated and the expected responses
    # (http://www.webdav.org/specs/rfc4918.html#rfc.section.9.10)
    def lock(args)
      raise NotImplemented
    end
    
    def unlock(token)
      raise NotImplemented
    end
    
    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      raise NotImplementedError
    end

    def ==(other)
      path == other.path
    end

    def name
      File.basename(path)
    end

    def display_name
      name
    end
    
    def child(name, option={})
      self.class.new(path + '/' + name, options)
    end
    
    def property_names
      %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    end
    
    def get_property(name)
      case name
      when 'resourcetype'     then resource_type
      when 'displayname'      then display_name
      when 'creationdate'     then creation_date.xmlschema 
      when 'getcontentlength' then content_length.to_s
      when 'getcontenttype'   then content_type
      when 'getetag'          then etag
      when 'getlastmodified'  then last_modified.httpdate
      end
    end

    def set_property(name, value)
      case name
      when 'resourcetype'    then self.resource_type = value
      when 'getcontenttype'  then self.content_type = value
      when 'getetag'         then self.etag = value
      when 'getlastmodified' then self.last_modified = Time.httpdate(value)
      end
    rescue ArgumentError
      raise HTTPStatus::Conflict
    end

    def remove_property(name)
      raise HTTPStatus::Forbidden
    end

    def parent
      elements = @path.scan(/[^\/]+/)
      return nil if elements.empty?
      self.class.new('/' + elements[0..-2].to_a.join('/'), @options)
    end
    
    def descendants
      list = []
      children.each do |child|
        list << child
        list.concat(child.descendants)
      end
      list
    end

    def allows_redirect?
      %w(webdrive cyberduck webdavfs).include? request.user_agent.downcase
    end
    
  end

end
