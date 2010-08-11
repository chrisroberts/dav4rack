require 'logger'

module DAV4Rack
  # This is a simple wrapper for the Logger class. It allows easy access 
  # to log messages from the library.
  class Logger
    class << self
      # args:: Arguments for Logger -> [path, level] (level is optional)
      # Set the path to the log file.
      def set(*args)
        @@logger = ::Logger.new(args.first, 'weekly')
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