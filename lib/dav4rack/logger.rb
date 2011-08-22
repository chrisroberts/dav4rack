require 'logger'

module DAV4Rack
  # This is a simple wrapper for the Logger class. It allows easy access 
  # to log messages from the library.
  class Logger
    class << self
      # args:: Arguments for Logger -> [path, level] (level is optional) or a Logger instance
      # Set the path to the log file.
      def set(*args)
        if(args.first.is_a?(Logger))
          @@logger = args.first
        else
          @@logger = ::Logger.new(args.first, 'weekly')
        end
        if(args.size > 1)
          @@logger.level = args[1]
        end
      end
      
      def method_missing(*args)
        if(defined? @@logger)
          @@logger.send *args
        end
      end
    end
  end
end
