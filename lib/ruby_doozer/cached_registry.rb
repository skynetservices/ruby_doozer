require 'thread_safe'
require 'gene_pool'
require 'semantic_logger'

#
# CachedRegistry
#
# Store information in doozer and subscribe to future changes
# and keep a local copy of the information in doozer
#
# Notifies registered subscribers when information has changed
#
# All paths specified are relative to the root_path. As such the root path
# is never returned, nor is it required when a path is supplied as input.
# For example, with a root_path of /foo/bar, any paths passed in will leave
# out the root_path: host/name
#
# Keeps a local copy in memory of all descendant values of the supplied root_path
# Allows high-frequency calls to retrieve registry data
# The cache will be kept in synch with any changes on the server
module RubyDoozer
  class CachedRegistry < Registry
    # Logging instance for this class
    include SemanticLogger::Loggable

    # Create a Registry instance to manage a path of information within doozer
    #
    # See RubyDoozer::Registry for complete list of options
    #
    def initialize(params)
      super
      @registry = ThreadSafe::Hash.new

      path = "#{@root_path}/**"
      doozer_pool.with_connection do |doozer|
        @current_revision = doozer.current_revision
        # Fetch all the configuration information from Doozer and set the internal copy
        doozer.walk(path, @current_revision).each do |node|
          @registry[relative_path(node.path)] = node.value
        end
      end

      # Start monitoring thread
      monitor_thread
    end

    # Retrieve the latest value from a specific path from the registry
    def [](path)
      @registry[path]
    end

    # Iterate over every key, value pair in the registry at the root_path
    #
    # Example:
    #   registry.each_pair {|k,v| puts "#{k} => #{v}"}
    def each_pair(&block)
      # Have to duplicate the registry otherwise changes to the registry will
      # interfere with the iterator
      @registry.dup.each_pair(&block)
    end

    # Returns [Array<String>] all paths in the registry
    def paths
      @registry.keys
    end

    # Returns a copy of the registry as a Hash
    def to_hash
      @registry.dup
    end

    # When an entry is created the block will be called
    #  Parameters
    #    path
    #      The relative path to watch for changes
    #    block
    #      The block to be called
    #
    #  Parameters passed to the block:
    #    path
    #      The path that was created
    #      Supplying a path of '*' means all paths
    #      Default: '*'
    #
    #    value
    #      New value from doozer
    #
    # Example:
    #   registry.on_update do |path, value|
    #     puts "#{path} was created with #{value}"
    #   end
    def on_create(path='*', &block)
      ((@create_subscribers ||= ThreadSafe::Hash.new)[path] ||= ThreadSafe::Array.new) << block
    end

    ############################
    protected

    # The path has been added or updated in the registry
    def changed(path, value)
      previous_value = @registry[path]

      # Update in memory copy
      @registry[path] = value

      # It is an update if we already have a value
      if previous_value
        # Call parent which will notify Updated Subscribers
        super
      else
        logger.debug { "Created: #{path} => #{value}" }

        return unless @create_subscribers

        # Subscribers to specific paths
        if subscribers = @create_subscribers[path]
          subscribers.each{|subscriber| subscriber.call(path, value)}
        end

        # Any subscribers for all events?
        if all_subscribers = @create_subscribers['*']
          all_subscribers.each{|subscriber| subscriber.call(path, value)}
        end
      end
    end

  end
end
