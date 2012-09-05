require 'pstore'

module DAV4Rack
  class FileResourceLock
    attr_accessor :path
    attr_accessor :token
    attr_accessor :timeout
    attr_accessor :depth
    attr_reader :created_at
    attr_reader :owner
    attr_reader :root

    class << self
      def explicitly_locked?(path, croot=nil)
        store = init_pstore(croot)
        !!store.transaction(true){
          store[:paths][path]
        }
      end

      def implicilty_locked?(path, croot=nil)
        store = init_pstore(croot)
        !!store.transaction(true){
          store[:paths].keys.detect do |check|
            check.start_with?(path)
          end
        }
      end

      def find_by_path(path, croot=nil)
        lock = self.class.new(:path => path, :root => croot)
        lock.token.nil? ? nil : lock
      end

      def find_by_token(token, croot=nil)
        store = init_pstore(croot)
        struct = store.transaction(true){
          store[:tokens][token]
        }
        if(tok)
          self.class.new(:path => struct[:path], :root => croot)
        else
          nil
        end
      end

      def generate(path, token)
        lock = self.new
        lock.path = path
        lock.token = token
        lock.save
        lock
      end

      def root=(path)
        @root = path
      end

      def root
        @root || '/tmp/dav4rack'
      end

      def init_pstore(root)
        path = File.join(root, '.attribs', 'locks.pstore')
        FileUtils.mkdir_p(File.dirname(path)) unless File.directory?(File.dirname(path))
        store = IS_18 ? PStore.new(path) : PStore.new(path, true)
        store.transaction do
          store[:paths] = {}
          store[:tokens] = {}
          store.commit
        end
      end
    end

    def initialize(args={})
      @store = init_pstore(args[:root])
      @max_timeout = args[:max_timeout] || 86400
      @default_timeout = args[:max_timeout] || 60
      @path = args[:path]
      @root = args[:root]
      @owner = args[:owner]
      load_if_exists!
      @new_record = true if token.nil?
    end

    def owner?(user)
      user == owner
    end

    def reload
      load_if_exists
      self
    end

    def remaining_timeout
      t = timeout.to_i - (Time.now.to_i - created_at.to_i)
      t < 0 ? 0 : t
    end

    def save
      struct = {
        :path => path, 
        :token => token, 
        :timeout => timeout, 
        :depth => depth,
        :created_at => Time.now,
        :owner => owner
      }
      @store.transaction do
        @store[:paths][path] = struct
        @store[:tokens][token] = struct
        @store.commit
      end
      @new_record = false
      self
    end

    def destroy
      @store.transaction do
        @store[:paths].delete(path)
        @store[:tokens].delete(token)
        @store.commit
      end
      nil
    end

    private

    def load_if_exists!
      struct = @store.transaction do
        @store[:paths][path]
      end
      @path = struct[:path]
      @token = struct[:token]
      @timeout = struct[:timeout]
      @depth = struct[:depth]
      @created_at = struct[:created_at]
      @owner = struct[:owner]
      self
    end

  end
end
