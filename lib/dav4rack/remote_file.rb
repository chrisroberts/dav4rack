require 'net/http'
require 'uri'
require 'digest/sha1'
require 'rack/file'

module DAV4Rack
  
  class RemoteFile < Rack::File
    
    attr_accessor :path
    
    alias :to_path :path
    
    # path:: Path to remote file
    # args:: Optional argument hash. Allowed keys: :size, :mime_type, :last_modified
    # Create a reference to a remote file. 
    # NOTE: HTTPError will be raised if path does not return 200 result
    def initialize(path, args={})
      @fpath = args[:url]
      @size = args[:size] || nil
      @mime_type = args[:mime_type] || 'text/plain'
      @modified = args[:last_modified] || nil
      @cache = args[:cache_directory] || nil
      cached_file = @cache + '/' + Digest::SHA1.hexdigest(@fpath)
      if(File.exists?(cached_file))
        @root = ''
        @path_info = cached_file
        @path = @path_info
      else
        begin
          @cf = File.open(cached_file, 'w+')
        rescue
          @cf = nil
        end
        @uri = URI.parse(path)
        @con = Net::HTTP.new(@uri.host, @uri.port)
        @call_path = @uri.path + (@uri.query ? "?#{@uri.query}" : '')
        res = @con.request_get(@call_path)
        @heads = res.to_hash
        res.value
        @store = nil
        self.public_methods.each do |method|
          m = method.to_s.dup
          next unless m.slice!(0,7) == 'remote_'
          self.class.class_eval "undef :'#{m}'"
          self.class.class_eval "alias :'#{m}' :'#{method}'"
        end
      end
    end

    def remote_serving
      [200, {
             "Last-Modified"  => last_modified,
             "Content-Type"   => content_type,
             "Content-Length" => size
            }, self]
    end
    
    
    def remote_call(env)
      dup._call(env)
    end
    
    def remote__call(env)
      serving
    end
    
    def remote_each
      if(@store)
        yield @store
      else
        @con.request_get(@call_path) do |res|
          res.read_body(@store) do |part|
            @cf.write part if @cf
            yield part
          end
        end
      end
    end
    
    def size
      @heads['content-length'] || @size
    end
    
    private
    
    def content_type
      @mime_type || @heads['content-type']
    end
    
    def last_modified
      @heads['last-modified'] || @modified
    end

  end
end
