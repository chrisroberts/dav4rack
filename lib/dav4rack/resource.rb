require 'uuidtools'

module DAV4Rack
  
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
    attr_reader :path, :options, :public_path, :request
    @@blocks = {:before => {}, :after => {}}
    
    class << self
      
      # This lets us define a bunch of before and after blocks that are
      # either called before all methods on the resource, or only specific
      # methods on the resource
      def method_missing(*args, &block)
        m = args.shift
        parts = m.to_s.split('_')
        type = parts.shift.to_s.to_sym
        method = parts.empty? ? nil : parts.join('_').to_sym
        if(@@blocks[type] && block_given?)
          if(method)
            @@blocks[type][method] ||= []
            @@blocks[type][method] << block
          else
            @@blocks[type][:'__all__'] ||= []
            @@blocks[type][:'__all__'] << block
          end
        else
          raise NoMethodError.new("Undefined method #{m} for class #{self}")
        end
      end
      
    end
    
    include DAV4Rack::HTTPStatus
    
    # public_path:: Path received via request
    # path:: Internal resource path (Only different from public path when using root_uri's for webdav)
    # request:: Rack::Request
    # options:: Any options provided for this resource
    # Creates a new instance of the resource.
    # NOTE: path and public_path will only differ if the root_uri has been set for the resource. The
    #       controller will strip out the starting path so the resource can easily determine what
    #       it is working on. For example:
    #       request -> /my/webdav/directory/actual/path
    #       public_path -> /my/webdav/directory/actual/path
    #       path -> /actual/path
    # NOTE: Customized Resources should not use initialize for setup. Instead
    #       use the #setup method
    def initialize(public_path, path, request, options)
      skip_alias = [:authenticate]
      @public_path = public_path.dup
      @path = path.dup
      @request = request
      unless(options.has_key?(:lock_class))
        require 'dav4rack/lock_store'
        @lock_class = LockStore
      else
        @lock_class = options[:lock_class]
        raise NameError.new("Unknown lock type constant provided: #{@lock_class}") unless @lock_class.nil? || defined?(@lock_class)
      end
      @options = options.dup
      @max_timeout = options[:max_timeout] || 86400
      @default_timeout = options[:default_timeout] || 60
      @user = @options[:user] || request.ip
      setup if respond_to?(:setup)
      public_methods(false).each do |method|
        next if skip_alias.include?(method.to_sym) || method[0,4] == 'DAV_'
        self.class.class_eval "alias :'DAV_#{method}' :'#{method}'"
        self.class.class_eval "undef :'#{method}'"
      end
      @runner = lambda do |kind, method_name|
        [:'__all__', method_name.to_sym].each do |sym|
          if(@@blocks[kind] && @@blocks[kind][sym])
            @@blocks[kind][sym].each do |b|
              args = [self, sym == :'__all__' ? sym : nil].compact
              b.call(*args)
            end
          end
        end
      end
    end
    
    # This allows us to call before and after blocks
    def method_missing(*args)
      result = nil
      orig = args.shift
      @runner.call(:before, orig)
      m = orig[0,4] == 'DAV_' ? orig : "DAV_#{orig}" # Attempt to prevent insanity loop
      if(respond_to?(m))
        result = send m, *args
      else
        raise NoMethodError.new("Undefined method: #{orig} for class #{self}.")
      end
      @runner.call(:after, orig)
      result
    end
    
    # If this is a collection, return the child resources.
    def children
      raise NotImplementedError
    end

    # Is this resource a collection?
    def collection?
      raise NotImplementedError
    end

    # Does this resource exist?
    def exist?
      raise NotImplementedError
    end
    
    # Does the parent resource exist?
    def parent_exists?
      parent.exist?
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

    # Return the resource type. Generally only used to specify
    # resource is a collection.
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
      raise NotImplemented
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
      raise NotImplemented if @lock_class.nil?
      raise Conflict unless parent_exists?
      lock_check(args[:scope])
      lock = @lock_class.explicit_locks(@path).find{|l| l.scope == args[:scope] && l.kind == args[:type] && l.user == @user}
      unless(lock)
        token = UUIDTools::UUID.random_create.to_s
        lock = @lock_class.generate(@path, @user, token)
        lock.scope = args[:scope]
        lock.kind = args[:type]
        lock.owner = args[:owner]
        lock.depth = args[:depth].to_i
        if(args[:timeout])
          lock.timeout = args[:timeout] <= @max_timeout && args[:timeout] > 0 ? args[:timeout] : @max_timeout
        else
          lock.timeout = @default_timeout
        end
        lock.save if lock.respond_to? :save
      end
      begin
        lock_check(args[:type])
      rescue DAV4Rack::LockFailure => e
        lock.destroy
        raise e
      end
      [lock.remaining_timeout, lock.token]
    end

    # lock_scope:: scope of lock
    # Check if resource is locked. Raise DAV4Rack::LockFailure if locks are in place.
    def lock_check(lock_scope=nil)
      return unless @lock_class
      if(@lock_class.explicitly_locked?(@path))
        raise Locked if @lock_class.explicit_locks(@path).find_all{|l|l.scope == 'exclusive' && l.user != @user}.size > 0
      elsif(@lock_class.implicitly_locked?(@path))
        if(lock_scope.to_s == 'exclusive')
          locks = @lock_class.implicit_locks(@path)
          failure = DAV4Rack::LockFailure.new("Failed to lock: #{@path}")
          locks.each do |lock|
            failure.add_failure(@path, Locked)
          end
          raise failure
        else
          locks = @lock_class.implict_locks(@path).find_all{|l| l.scope == 'exclusive' && l.user != @user}
          if(locks.size > 0)
            failure = LockFailure.new("Failed to lock: #{@path}")
            locks.each do |lock|
              failure.add_failure(@path, Locked)
            end
            raise failure
          end
        end
      end
    end
    
    # token:: Lock token
    # Remove the given lock
    def unlock(token)
      raise NotImplemented if @lock_class.nil?
      token = token.slice(1, token.length - 2)
      raise BadRequest if token.nil? || token.empty?
      lock = @lock_class.find_by_token(token)
      raise Forbidden unless lock && lock.user == @user
      raise Conflict unless lock.path =~ /^#{Regexp.escape(@path)}.*$/
      lock.destroy
      delete if name[0,1] == '.' && @options[:delete_dotfiles]
      NoContent
    end
    
    
    # Create this resource as collection.
    def make_collection
      raise NotImplementedError
    end

    # other:: Resource
    # Returns if current resource is equal to other resource
    def ==(other)
      path == other.path
    end

    # Name of the resource
    def name
      File.basename(path)
    end

    # Name of the resource to be displayed to the client
    def display_name
      name
    end
    
    # Available properties
    def property_names
      %w(creationdate displayname getlastmodified getetag resourcetype getcontenttype getcontentlength)
    end
    
    # name:: String - Property name
    # Returns the value of the given property
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

    # name:: String - Property name
    # value:: New value
    # Set the property to the given value
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

    # name:: Property name
    # Remove the property from the resource
    def remove_property(name)
      raise HTTPStatus::Forbidden
    end

    # name:: Name of child
    # Create a new child with the given name
    # NOTE:: Include trailing '/' if child is collection
    def child(name)
      new_public = public_path.dup
      new_public = new_public + '/' unless new_public[-1,1] == '/'
      new_public = '/' + new_public unless new_public[0,1] == '/'
      new_path = path.dup
      new_path = new_path + '/' unless new_path[-1,1] == '/'
      new_path = '/' + new_path unless new_path[0,1] == '/'
      self.class.new("#{new_public}#{name}", "#{new_path}#{name}", request, options.merge(:user => @user))
    end
    
    # Return parent of this resource
    def parent
      elements = @path.scan(/[^\/]+/)
      return nil if elements.empty?
      self.class.new(('/' + @public_path.scan(/[^\/]+/)[0..-2].join('/')), ('/' + elements[0..-2].to_a.join('/')), @request, @options.merge(:user => @user))
    end
    
    # Return list of descendants
    def descendants
      list = []
      children.each do |child|
        list << child
        list.concat(child.descendants)
      end
      list
    end

    # Does client allow GET redirection
    def allows_redirect?
      %w(cyberduck konqueror).any?{|x| (request.respond_to?(:user_agent) ? request.user_agent.to_s.downcase : request.env['HTTP_USER_AGENT'].to_s.downcase) =~ /#{Regexp.escape(x)}/}
    end
    
  end

end
