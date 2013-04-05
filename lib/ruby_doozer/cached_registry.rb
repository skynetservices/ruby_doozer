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
# All paths specified are relative to the root_path. As such the root key
# is never returned, nor is it required when a key is supplied as input.
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

    # Create a Registry instance to manage information within doozer
    # and keep a local cached copy of the data in doozer to support
    # high-speed or frequent reads.
    #
    # Writes are sent to doozer and then replicate back to the local cache
    # only once doozer has updated its store
    #
    # See RubyDoozer::Registry for complete list of options
    #
    def initialize(params)
      super
      @cache = ThreadSafe::Hash.new

      key = "#{@root}/**"
      doozer_pool.with_connection do |doozer|
        @current_revision = doozer.current_revision
        # Fetch all the configuration information from Doozer and set the internal copy
        doozer.walk(key, @current_revision) do |key, value, revision|
          set_cached_value(relative_key(key), @deserializer.deserialize(value))
        end
      end

      # Start monitoring thread
      monitor_thread
    end

    # Retrieve the latest value from a specific key from the registry
    def [](key)
      @cache[key]
    end

    # Iterate over every key, value pair in the registry at the root_path
    #
    # Example:
    #   registry.each_pair {|k,v| puts "#{k} => #{v}"}
    def each_pair(&block)
      # Have to duplicate the registry otherwise changes to the registry will
      # interfere with the iterator
      @cache.dup.each_pair(&block)
    end

    # Returns [Array<String>] all keys in the registry
    def keys
      @cache.keys
    end

    # Returns a copy of the registry as a Hash
    def to_h
      @cache.dup
    end

    # When an entry is created the block will be called
    #  Parameters
    #    key
    #      The relative key to watch for changes
    #    block
    #      The block to be called
    #
    #  Parameters passed to the block:
    #    key
    #      The key that was created
    #      Supplying a key of '*' means all paths
    #      Default: '*'
    #
    #    value
    #      New value from doozer
    #
    # Example:
    #   registry.on_update do |key, value, revision|
    #     puts "#{key} was created with #{value}"
    #   end
    def on_create(key='*', &block)
      ((@create_subscribers ||= ThreadSafe::Hash.new)[key] ||= ThreadSafe::Array.new) << block
    end

    ############################
    protected

    # Sets the internal value for a specific key
    # Called on startup to fill the internal registry and then every time a value
    # changes in doozer
    # This method can be replaced by derived Registries to change the format of
    # the registry
    def set_cached_value(doozer_path, value)
      @cache[doozer_path] = value
    end

    # Returns the internal value for a specific key
    # Called every time a value changes in doozer
    # This method can be replaced by derived Registries to change the format of
    # the registry
    def get_cached_value(doozer_path)
      @cache[doozer_path]
    end

    # The key has been added or updated in the registry
    def changed(key, value, revision)
      previous_value = get_cached_value(key)

      # Update in memory copy
      set_cached_value(key, value)

      # It is an update if we already have a value
      if previous_value
        # Call parent which will notify Updated Subscribers
        super
      else
        logger.debug "Created: #{key}", value

        return unless @create_subscribers

        # Subscribers to specific paths
        if subscribers = @create_subscribers[key]
          subscribers.each{|subscriber| subscriber.call(key, value, revision)}
        end

        # Any subscribers for all events?
        if all_subscribers = @create_subscribers['*']
          all_subscribers.each{|subscriber| subscriber.call(key, value, revision)}
        end
      end
    end

  end
end
