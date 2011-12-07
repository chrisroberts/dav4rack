require 'webrick/httputils'

module DAV4Rack

  class FileResource < Resource
    
    include WEBrick::HTTPUtils
    
    # If this is a collection, return the child resources.
    def children
      Dir[file_path + '/*'].map do |path|
        child File.basename(path)
      end
    end

    # Is this resource a collection?
    def collection?
      File.directory?(file_path)
    end

    # Does this recource exist?
    def exist?
      File.exist?(file_path)
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
      File.utime(Time.now, time, file_path)
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
        File.unlink(file_path)
      end
      NoContent
    end
    
    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest, overwrite = false)
      if(dest.path == path)
        Conflict
      elsif(stat.directory?)
        dest.make_collection
        FileUtils.cp_r("#{file_path}/.", "#{dest.send(:file_path)}/")
        OK
      else
        exists = File.exists?(file_path)
        if(exists && !overwrite)
          PreconditionFailed
        else
          open(file_path, "rb") do |file|
            dest.write(file)
          end
          exists ? NoContent : Created
        end
      end
    end
  
    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(*args)
      copy(*args)
      delete
      OK
    end
    
    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      Dir.mkdir(file_path)
      Created
    end
  
    # Write to this resource from given IO.
    def write(io)
      tempfile = "#{file_path}.#{Process.pid}.#{object_id}"
      
      open(tempfile, "wb") do |file|
        while part = io.read(8192)
          file << part
        end
      end

      File.rename(tempfile, file_path)      
    ensure
      File.unlink(tempfile) rescue nil
    end
    
    private

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
      root + '/' + path
    end

    def stat
      @stat ||= File.stat(file_path)
    end

  end

end
