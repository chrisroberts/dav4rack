require 'digest/sha1'

module RackDAV

  class InterceptorResource < Resource
    attr_reader :path, :options
    
    def initialize(*args)
      super
      @root_paths = @options[:mappings].keys
      @mappings = @options[:mappings]
    end
        
    # If this is a collection, return the child resources.
    def children
      childs = @root_paths.find_all{|x|x =~ /^#{Regexp.escape(@path)}/}
      childs = childs.map{|a| child a.gsub(/^#{Regexp.escape(@path)}/, '').split('/').delete_if{|x|x.empty?}.first }.flatten
    end

    # Is this resource a collection?
    def collection?
      true if exist?
    end

    # Does this recource exist?
    def exist?
      !@root_paths.find_all{|x| x =~ /^#{Regexp.escape(@path)}/}.empty?
    end
    
    # Return the creation time.
    def creation_date
      Time.now
    end

    # Return the time of last modification.
    def last_modified
      Time.now
    end
    
    # Set the time of last modification.
    def last_modified=(time)
      Time.now
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
      Digest::SHA1.hexdigest(@path)
    end

    # Return the mime type of this resource.
    def content_type
      'text/html'
    end

    # Return the size in bytes for this resource.
    def content_length
      0
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      raise Forbidden
    end

    # HTTP PUT request.
    #
    # Save the content of the request.body.
    def put(request, response)
      raise Forbidden
    end
    
    # HTTP POST request.
    #
    # Usually forbidden.
    def post(request, response)
      raise Forbidden
    end
    
    # HTTP DELETE request.
    #
    # Delete this resource.
    def delete
      raise Forbidden
    end
    
    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest)
      raise Forbidden
    end
  
    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest)
      raise Forbidden
    end
    
    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
      raise Forbidden
    end

    def ==(other)
      path == other.path
    end

    def name
      File.basename(path)
    end

    def display_name
      File.basename(path.to_s)
    end
    
    def child(name, option={})
      new_path = path.dup
      new_path = '/' + new_path unless new_path[0,1] == '/'
      new_path.slice!(-1) if new_path[-1,1] == '/'
      name = '/' + name unless name[-1,1] == '/'
      new_path = "#{new_path}#{name}"
      new_public = public_path.dup
      new_public = '/' + new_public unless new_public[0,1] == '/'
      new_public.slice!(-1) if new_public[-1,1] == '/'
      new_public = "#{new_public}#{name}"
      if(key = @root_paths.find{|x| new_path =~ /^#{Regexp.escape(x.downcase)}\/?/})
        @mappings[key][:class].new(new_public, new_path.gsub(key, ''), @mappings[key][:options] ? @mappings[key][:options] : options)
      else
        self.class.new(new_public, new_path, options)
      end
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

  end

end
