require 'net/http'
require 'uri'

module RackDAV
  
  class RemoteFile
    
    attr_accessor :path
    
    alias :to_path :path
    
    # path:: Path to remote file
    # args:: Optional argument hash. Allowed keys: :size, :mime_type, :last_modified
    # Create a reference to a remote file. 
    # NOTE: HTTPError will be raised if path does not return 200 result
    def initialize(path, args={})
      @path = path
      @size = args[:size] || nil
      @mime_type = args[:mime_type] || 'text/plain'
      @modified = args[:last_modified] || nil
      @uri = URI.parse(@path)
      @con = Net::HTTP.new(@uri.host, @uri.port)
      @call_path = @uri.path + (@uri.query ? "?#{@uri.query}" : '')
      res = @con.request_get(@call_path)
      @heads = res.to_hash
      res.value
      @store = nil
    end
    
    def size
      @heads['content-length'] || @size
    end
    
    def content_type
      @mime_type || @heads['content-type']
    end
    
    def last_modified
      @heads['last-modified'] || @modified
    end
    
    def call(env)
      dup._call(env)
    end

    def _call(env)
      serving
    end
    
    def each
      if(@store)
        yield @store
      else
        @con.request_get(@call_path) do |res|
          res.read_body(@store) do |part|
            yield part
          end
        end
      end
    end
  end
end
