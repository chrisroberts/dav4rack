# encoding: UTF-8

require 'pstore'
require 'webrick/httputils'
require 'dav4rack/file_resource_lock'

module DAV4Rack

  class FileResource < Resource

    include WEBrick::HTTPUtils
    include DAV4Rack::Utils

    # If this is a collection, return the child resources.
    def children
      Dir[file_path + '/*'].map do |path|
        child ::File.basename(path)
      end
    end

    # Is this resource a collection?
    def collection?
      ::File.directory?(file_path)
    end

    # Does this recource exist?
    def exist?
      ::File.exist?(file_path)
    end

    # Return the creation time.
    def creation_date
      stat.ctime
    end

    # Return the time of last modification.
    def last_modified
      stat.mtime
    end

    # Set the time of last modification.
    def last_modified=(time)
      ::File.utime(Time.now, time, file_path)
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      sprintf('%x-%x-%x', stat.ino, stat.size, stat.mtime.to_i)
    end

    # Return the mime type of this resource.
    def content_type
      if stat.directory?
        "text/html"
      else
        mime_type(file_path, DefaultMimeTypes)
      end
    end

    # Return the size in bytes for this resource.
    def content_length
      stat.size
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      raise NotFound unless exist?
      if stat.directory?
        response.body = ""
        Rack::Directory.new(root).call(request.env)[2].each do |line|
          response.body << line
        end
        response['Content-Length'] = response.body.bytesize.to_s
      else
        file = Rack::File.new(root)
        response.body = file
      end
      OK
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      write(request.body)
      Created
    end

    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise HTTPStatus::Forbidden
    end

    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      if stat.directory?
        FileUtils.rm_rf(file_path)
      else
        ::File.unlink(file_path)
      end
      ::File.unlink(prop_path) if ::File.exists?(prop_path)
      @_prop_hash = nil
      NoContent
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    # Copy this resource to given destination resource.
    def copy(dest, overwrite)
      if(collection?)
        if(dest.exist?)
          if(dest.collection? && overwrite)
            FileUtils.cp_r(file_path, dest.send(:file_path))
            Created
          else
            if(overwrite)
              FileUtils.rm(dest.send(:file_path))
              FileUtils.cp_r(file_path, dest.send(:file_path))
              NoContent
            else
              PreconditionFailed
            end
          end
        else
          FileUtils.cp_r(file_path, dest.send(:file_path))
          Created
        end
      else
        if(dest.exist? && !overwrite)
          PreconditionFailed
        else
          if(::File.directory?(::File.dirname(dest.send(:file_path))))
            new = !dest.exist?
            if(dest.collection? && dest.exist?)
              FileUtils.rm_rf(dest.send(:file_path))
            end
            FileUtils.cp(file_path, dest.send(:file_path).sub(/\/$/, ''))
            FileUtils.cp(prop_path, dest.prop_path) if ::File.exist? prop_path
            new ? Created : NoContent
          else
            Conflict
          end
        end
      end
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(*args)
      result = copy(*args)
      delete if [Created, NoContent].include?(result)
      result
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      if(request.body.read.to_s == '')
        if(::File.directory?(file_path))
          MethodNotAllowed
        else
          if(::File.directory?(::File.dirname(file_path)) && !::File.exists?(file_path))
            Dir.mkdir(file_path)
            Created
          else
            Conflict
          end
        end
      else
        UnsupportedMediaType
      end
    end

    # Write to this resource from given IO.
    def write(io)
      tempfile = "#{file_path}.#{Process.pid}.#{object_id}"
      open(tempfile, "wb") do |file|
        while part = io.read(8192)
          file << part
        end
      end
      ::File.rename(tempfile, file_path)
    ensure
      ::File.unlink(tempfile) rescue nil
    end

    # name:: String - Property name
    # Returns the value of the given property
    def get_property(name)
      begin
        super
      rescue NotImplemented
        custom_props(name)
      end
    end

    # name:: String - Property name
    # value:: New value
    # Set the property to the given value
    def set_property(name, value)
      begin
        super
      rescue NotImplemented
        set_custom_props(name,value)
      end
    end

    def remove_property(element)
      prop_hash.transaction do
        prop_hash.delete(to_element_key(element))
        prop_hash.commit
      end
      val = prop_hash.transaction{ prop_hash[to_element_key(element)] }
    end

    def lock(args)
      unless(parent_exists?)
        Conflict
      else
        lock_check(args[:type])
        lock = FileResourceLock.explicit_locks(@path, root, :scope => args[:scope], :kind => args[:type], :user => @user)
        unless(lock)
          token = UUIDTools::UUID.random_create.to_s
          lock = FileResourceLock.generate(@path, @user, token, root)
          lock.scope = args[:scope]
          lock.kind = args[:type]
          lock.owner = args[:owner]
          lock.depth = args[:depth]
          if(args[:timeout])
            lock.timeout = args[:timeout] <= @max_timeout && args[:timeout] > 0 ? args[:timeout] : @max_timeout
          else
            lock.timeout = @default_timeout
          end
          lock.save
        end
        begin
          lock_check(args[:type])
        rescue DAV4Rack::LockFailure => lock_failure
          lock.destroy
          raise lock_failure
        rescue HTTPStatus::Status => status
          status
        end
        [lock.remaining_timeout, lock.token]
      end
    end

    def unlock(token)
      token = token.slice(1, token.length - 2)
      if(token.nil? || token.empty?)
        BadRequest
      else
        lock = FileResourceLock.find_by_token(token)
        if(lock.nil? || lock.user_id != @user.id)
          Forbidden
        elsif(lock.path !~ /^#{Regexp.escape(@path)}.*$/)
          Conflict
        else
          lock.destroy
          NoContent
        end
      end
    end

    protected

    def lock_check(lock_type=nil)
      if(FileResourceLock.explicitly_locked?(@path, root))
        raise Locked if lock_type && lock_type == 'exclusive'
        #raise Locked if FileResourceLock.explicit_locks(@path, root).find(:all, :conditions => ["scope = 'exclusive' AND user_id != ?", @user.id]).size > 0
      elsif(FileResourceLock.implicitly_locked?(@path, root))
        if(lock_type.to_s == 'exclusive')
          locks = FileResourceLock.implicit_locks(@path)
          failure = DAV4Rack::LockFailure.new("Failed to lock: #{@path}")
          locks.each do |lock|
            failure.add_failure(@path, Locked)
          end
          raise failure
        else
          locks = FileResourceLock.implict_locks(@path).find(:all, :conditions => ["scope = 'exclusive' AND user_id != ?", @user.id])
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

    def set_custom_props(element, val)
      prop_hash.transaction do
        prop_hash[to_element_key(element)] = val
        prop_hash.commit
      end
    end

    def custom_props(element)
      val = prop_hash.transaction(true) do
        prop_hash[to_element_key(element)]
      end
      raise NotFound unless val
      val
    end

    def store_directory
      path = ::File.join(root, '.attrib_store')
      unless(::File.directory?(::File.dirname(path)))
        FileUtils.mkdir_p(::File.dirname(path))
      end
      path
    end

    def prop_path
      path = ::File.join(store_directory, "#{::File.join(::File.dirname(file_path), ::File.basename(file_path)).gsub('/', '_')}.pstore")
      unless(::File.directory?(::File.dirname(path)))
        FileUtils.mkdir_p(::File.dirname(path))
      end
      path
    end

    def lock_path
      path = ::File.join(store_directory, 'locks.pstore')
      unless(::File.directory?(::File.dirname(path)))
        FileUtils.mkdir_p(::File.dirname(path))
      end
      path
    end

    def prop_hash
      @_prop_hash ||= IS_18 ? PStore.new(prop_path) : PStore.new(prop_path, true)
    end

    def authenticate(user, pass)
      if(options[:username])
        options[:username] == user && options[:password] == pass
      else
        true
      end
    end

    def root
      @options[:root]
    end

    def file_path
      ::File.join(root, path)
    end

    def stat
      @stat ||= ::File.stat(file_path)
    end

  end

end
