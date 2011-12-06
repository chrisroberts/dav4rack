# coding: utf-8
require 'mime/types'

module DAV4Rack

  class MongoResource < DAV4Rack::Resource

#    @@logger = Rails.logger

    def initialize(public_path, path, request, response, options)
      # 'ASCII-8BIT'で渡される場合があるので'UTF-8'を指定しておく
      _force_encoding!(public_path)
      _force_encoding!(path)
      super(public_path, path, request, response, options)
      @filesystem = Mongo::GridFileSystem.new(Mongoid.database)
      @collection = Mongoid.database.collection('fs.files')
      if options[:bson]
        @bson = options[:bson]
      elsif path.length <= 1
        # ルートの場合 (''の場合と'/'の場合がある)
        @bson = {'filename' => root + '/'}
      else
        # ファイルかディレクトリが、パラメータだけでは判断できない。ので \/? が必要。
        # だから、ディレクトリと同名のファイルは、作成できない。
        @bson = @collection.find_one({:filename => /^#{Regexp.escape(file_path)}\/?$/}) rescue nil
      end
    end

    def child(bson)
      path = remove(bson['filename'], root)
      public_path = @options[:root_uri_path] + path
      @options[:bson] = bson
      self.class.new(public_path, path, @request, @response, @options)
    end

    # If this is a collection, return the child resources.
    def children
#     Dir[file_path + '/*'].map do |path|
#       child File.basename(path)
#     end
      @collection.find({:filename => /^#{Regexp.escape(@bson['filename'])}[^\/]+\/?$/}).map do |bson|
        child bson
      end
    end

    # Is this resource a collection?
    def collection?
#     File.directory?(file_path)
      @bson && _collection?(@bson['filename'])
    end

    # Does this recource exist?
    def exist?
#     File.exist?(file_path)
      @bson
    end

    # Return the creation time.
    def creation_date
#     stat.ctime
      @bson['uploadDate'] || Date.new
    end

    # Return the time of last modification.
    def last_modified
#     stat.mtime
      @bson['uploadDate'] || Date.new
    end

    # Set the time of last modification.
    def last_modified=(time)
#      File.utime(Time.now, time, file_path)
    end

    # Return an Etag, an unique hash value for this resource.
    def etag
#     sprintf('%x-%x-%x', stat.ino, stat.size, stat.mtime.to_i)
      @bson['_id'].to_s
    end

    # Return the mime type of this resource.
    def content_type
#     if stat.directory?
#       "text/html"
#     else 
#       mime_type(file_path, DefaultMimeTypes)
#     end
      @bson['contentType'] || "text/html"
    end

    # Return the size in bytes for this resource.
    def content_length
#     stat.size
      @bson['length'] || 0
    end

    # HTTP GET request.
    #
    # Write the content of the resource to the response.body.
    def get(request, response)
      raise NotFound unless exist?
#     if stat.directory?
#       response.body = ""
#       Rack::Directory.new(root).call(request.env)[2].each do |line|
#         response.body << line
#       end
#       response['Content-Length'] = response.body.size.to_s
#     else
#       file = Rack::File.new(root)
#       response.body = file
#     end
      if collection?
        response.body = "<html>"
        response.body << "<h2>" + file_path.html_safe + "</h2>"
        children.each do |child|
          name = child.file_path.html_safe
          path = child.public_path
          response.body << "<a href='" + path + "'>" + name + "</a>"
          response.body << "</br>"
        end
        response.body << "</html>"
        response['Content-Length'] = response.body.size.to_s
        response['Content-Type'] = 'text/html'
      else
        @filesystem.open(file_path, 'r') do |f|
          response.body = f
          response['Content-Type'] = @bson['contentType']
        end
      end

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
#     if stat.directory?
#       FileUtils.rm_rf(file_path)
#     else
#       File.unlink(file_path)
#     end
      if collection?
        @collection.find({:filename => /^#{Regexp.escape(@bson['filename'])}/}).each do |bson|
          @collection.remove(bson)
        end
      else
        @collection.remove(@bson)
      end
      NoContent
    end

    # HTTP COPY request.
    #
    # Copy this resource to given destination resource.
    def copy(dest, overwrite = false)
#     if(dest.path == path)
#       Conflict
#     elsif(stat.directory?)
#       dest.make_collection
#       FileUtils.cp_r("#{file_path}/.", "#{dest.send(:file_path)}/")
#       OK
#     else
#       exists = File.exists?(file_path)
#       if(exists && !overwrite)
#         PreconditionFailed
#       else
#         open(file_path, "rb") do |file|
#           dest.write(file)
#         end
#         exists ? NoContent : Created
#       end
#     end

      # ディレクトリなら末尾に「/」をつける。
      # (dstにもともと「/」が付いているかどうか、クライアントに依存している)
      # CarotDAV : 「/」が付いていない
      # TeamFile : 「/」が付いている
      dest.collection! if collection?

      src = @bson['filename']
      dst = dest.file_path
      exists = nil

      @collection.find({:filename => /^#{Regexp.escape(src)}/}).each do |bson|
        src_name = bson['filename']
        dst_name = dst + src_name.slice(src.length, src_name.length)

        exists = @collection.find_one({:filename => dst_name}) rescue nil

        return PreconditionFailed if (exists && !overwrite && !collection?)

        @filesystem.open(src_name, "r") do |src|
        @filesystem.open(dst_name, "w") do |dst|
          dst.write(src) if src.file_length > 0
        end
        end

        @collection.remove(exists) if exists
      end

      collection? ? Created : (exists ? NoContent : Created)
    end

    # HTTP MOVE request.
    #
    # Move this resource to given destination resource.
    def move(dest, overwrite = false)

      # ディレクトリなら末尾に「/」をつける。
      # (dstにもともと「/」が付いているかどうか、クライアントに依存している)
      # CarotDAV : 「/」が付いていない
      # TeamFile : 「/」が付いている
      dest.collection! if collection?

      src = @bson['filename']
      dst = dest.file_path
      exists = nil

      @collection.find({:filename => /^#{Regexp.escape(src)}/}).each do |bson|
        src_name = bson['filename']
        dst_name = dst + src_name.slice(src.length, src_name.length)

        exists = @collection.find_one({:filename => dst_name}) rescue nil

        # http://mongoid.org/docs/persistence/atomic.html
        # http://rubydoc.info/github/mongoid/mongoid/master/Mongoid/Collection#update-instance_method
        @collection.update({'_id' => bson['_id']}, {'$set' => {'filename' => dst_name}}, :safe => true)
        
        @collection.remove(exists) if exists
      end

      collection? ? Created : (exists ? NoContent : Created)
    end

    # HTTP MKCOL request.
    #
    # Create this resource as collection.
    def make_collection
#     Dir.mkdir(file_path)
#     Created

      # ディレクトリなら末尾に「/」をつける。
      # (dstにもともと「/」が付いているかどうか、クライアントに依存している)
      # CarotDAV : 「/」が付いていない
      # TeamFile : 「/」が付いている
      collection!

      bson = @collection.find_one({:filename => file_path}) rescue nil

      # 0バイトのファイルを作成しディレクトリの代わりとする
      @filesystem.open(file_path, "w") { |f| } if !bson
 
#      @@logger.error('make_collection : ' + file_path)

      Created
    end

    # Write to this resource from given IO.
    def write(io)
#     tempfile = "#{file_path}.#{Process.pid}.#{object_id}"
#     open(tempfile, "wb") do |file|
#       while part = io.read(8192)
#         file << part
#       end
#     end
#     File.rename(tempfile, file_path)
#     ensure
#       File.unlink(tempfile) rescue nil

      # 同名のファイルができないように
      bson = @collection.find_one({:filename => file_path}) rescue nil

      @filesystem.open(file_path, "w", :content_type => _content_type(file_path)) { |f| f.write(io) }

      # 同名のファイルができないように
      @collection.remove(bson) if bson

    end

    protected

    def file_path
      root + path
    end

    # ファイル名の末尾に「/」を付加してディレクトリ（コレクション）とする
    def collection!
      path << '/' if !_collection?(path)
    end

    private

    def _content_type(filename)
      MIME::Types.type_for(filename).first.to_s || 'text/html'
    end

    def authenticate(user, pass)
      if(options[:username])
        options[:username] == user && options[:password] == pass
      else
        true
      end
    end

    # path1の先頭からpath2を取り除く
    def remove(path1, path2)
      path1.slice(path2.length, path1.length)
    end

    def root
      @options[:root]
    end

    # ファイル名の末尾が「/」のファイルをディレクトリ（コレクション）とする
    def _collection?(path)
      path && path[-1].chr == '/'
    end

    # 'ASCII-8BIT'で渡される場合があるので'UTF-8'を指定しておく
    def _force_encoding!(str)
      str.force_encoding('UTF-8')
    end

  end

end
