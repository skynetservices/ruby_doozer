require 'thread_safe'
require 'gene_pool'
require 'semantic_logger'

#
# Registry
#
# Store information in doozer and subscribe to future changes
#
# Notifies registered subscribers when information has changed
#
# All paths specified are relative to the root_path. As such the root path
# is never returned, nor is it required when a path is supplied as input.
# For example, with a root_path of /foo/bar, any paths passed in will leave
# out the root_path: host/name
#
module RubyDoozer
  class Registry
    # Logging instance for this class
    include SemanticLogger::Loggable

    attr_reader :doozer_config, :doozer_pool

    # Create a Registry instance to manage a path of information within doozer
    #
    # :root_path [String]
    #   Root path to load and then monitor for changes
    #   It is not recommended to set the root_path to "/" as it will generate
    #   significant traffic since it will also monitor Doozer Admin changes
    #   Mandatory
    #
    # :cache [Boolean]
    #   Keep a local copy in memory of all descendant values of the supplied root_path
    #   Allows high-frequency calls to retrieve registry data
    #   The cache will be kept in synch with any changes on the server
    #   Default: true
    #
    # :doozer [Hash]
    #   Doozer configuration information
    #
    #   :servers [Array of String]
    #     Array of URL's of doozer servers to connect to with port numbers
    #     ['server1:2000', 'server2:2000']
    #
    #     An attempt will be made to connect to alternative servers when the
    #     current server cannot be connected to
    #     Default: ['127.0.0.1:8046']
    #
    #   :read_timeout [Float]
    #     Time in seconds to timeout on read
    #     Can be overridden by supplying a timeout in the read call
    #     Default: 5
    #
    #   :connect_timeout [Float]
    #     Time in seconds to timeout when trying to connect to the server
    #     Default: 3
    #
    #   :connect_retry_count [Fixnum]
    #     Number of times to retry connecting when a connection fails
    #     Default: 10
    #
    #   :connect_retry_interval [Float]
    #     Number of seconds between connection retry attempts after the first failed attempt
    #     Default: 0.5
    #
    #   :server_selector [Symbol|Proc]
    #     When multiple servers are supplied using :servers, this option will
    #     determine which server is selected from the list
    #       :ordered
    #         Select a server in the order supplied in the array, with the first
    #         having the highest priority. The second server will only be connected
    #         to if the first server is unreachable
    #       :random
    #         Randomly select a server from the list every time a connection
    #         is established, including during automatic connection recovery.
    #       Proc:
    #         When a Proc is supplied, it will be called passing in the list
    #         of servers. The Proc must return one server name
    #           Example:
    #             :server_selector => Proc.new do |servers|
    #               servers.last
    #             end
    #       Default: :random
    #
    #   :pool_size [Integer]
    #     Maximum size of the connection pool to doozer
    #     Default: 10
    #
    def initialize(params)
      params = params.dup
      @root_path = params.delete(:root_path)
      raise "Missing mandatory parameter :root_path" unless @root_path

      # Add leading '/' to root_path if missing
      @root_path = "/#{@root_path}" unless @root_path.start_with?('/')

      # Strip trailing '/' if supplied
      @root_path = @root_path[0..-2] if @root_path.end_with?("/")
      @root_path_with_trail = "#{@root_path}/"

      local_copy = params.delete(:cache)
      @registry = (local_copy == false) ? nil : ThreadSafe::Hash.new

      @doozer_config = params.delete(:doozer) || {}
      @doozer_config[:servers]                ||= ['127.0.0.1:8046']
      @doozer_config[:read_timeout]           ||= 5
      @doozer_config[:connect_timeout]        ||= 3
      @doozer_config[:connect_retry_interval] ||= 0.5
      @doozer_config[:connect_retry_count]    ||= 10
      @doozer_config[:server_selector]        ||= :random

      # Connection pool settings
      @doozer_pool = GenePool.new(
        :name         =>"Doozer Connection Pool",
        :pool_size    => @doozer_config.delete(:pool_size) || 10,
        :timeout      => @doozer_config.delete(:pool_timeout) || 30,
        :warn_timeout => @doozer_config.delete(:pool_warn_timeout) || 5,
        :idle_timeout => @doozer_config.delete(:pool_idle_timeout) || 600,
        :logger       => logger,
        :close_proc   => :close
      ) do
        RubyDoozer::Client.new(@doozer_config)
      end

      @create_subscribers = ThreadSafe::Hash.new
      @update_subscribers = ThreadSafe::Hash.new
      @delete_subscribers = ThreadSafe::Hash.new

      revision = nil
      path = "#{@root_path}/**"
      doozer_pool.with_connection do |doozer|
        revision = doozer.current_revision
        if @registry
          # Fetch all the configuration information from Doozer and set the internal copy
          doozer.walk(path, revision).each do |node|
            @registry[relative_path(node.path)] = node.value
          end
        end
      end

      # Start monitoring thread to keep the registry in synch with doozer
      @monitor_thread = Thread.new { watch_registry(path, revision + 1) }

      # Generate warning log entries for any unknown configuration options
      params.each_pair {|k,v| logger.warn "Ignoring unknown configuration option: #{k}"}
    end

    # Retrieve the latest value from a specific path from the registry
    # If :cache was set to false on the initializer this call will
    # make a network call to doozer to retrieve the current value
    # Otherwise it is an in memory call and can be called frequently
    def [](path)
      if @registry
        @registry[path]
      else
        doozer_pool.with_connection do |doozer|
          doozer[full_path(path)]
        end
      end
    end

    # Replace the latest value at a specific path
    # The in-memory copy will be updated when doozer sends out the change
    # TODO Should we also update the in memory copy rather than wait for the change
    #      notification?
    def []=(path,value)
      doozer_pool.with_connection do |doozer|
        doozer[full_path(path)] = value
      end
    end

    # Delete the value at a specific path
    # The in-memory copy will be updated when doozer sends out the change
    # TODO Should we also delete the in memory copy rather than wait for the change
    #      notification?
    def delete(path)
      old_value = @registry[path] if @registry
      doozer_pool.with_connection do |doozer|
        doozer.delete(full_path(path))
      end
      old_value
    end

    # Iterate over every key, value pair in the registry at the root_path
    #
    # If :cache was set to false on the initializer this call will
    # make network calls to doozer to retrieve the current values
    # Otherwise it is an in memory call against a duplicate of the registry
    #
    # Example:
    #   registry.each_pair {|k,v| puts "#{k} => #{v}"}
    def each_pair(&block)
      if @registry
        @registry.dup.each_pair(&block)
      else
        path = "#{@root_path}/**"
        doozer_pool.with_connection do |doozer|
          doozer.walk(path, revision).each do |node|
            block.call(relative_path(node.path), node.value)
          end
        end
      end
    end

    # Returns a copy of the registry as a Hash
    def to_h
      if @registry
        @registry.dup
      else
        h = {}
        each_pair {|k,v| h[k] = v}
        h
      end
    end

    # Cleanup on process termination
    def finalize
      logger.info "Finalizing"
      if @monitor_thread
        @monitor_thread.kill
        @monitor_thread = nil
      end
      @doozer_pool.close if @doozer_pool
      @doozer_pool = nil
    end

    # When an entry is created the block will be called
    #  Parameters
    #    path
    #      The relative path _excluding_ the root_path to watch for changes
    #      #TODO Or a regular expression
    #    block
    #      The block to be called
    #
    #  Parameters passed to the block:
    #    path
    #      The path that was created
    #
    #    value
    #      New value from doozer
    #
    # Example:
    #   registry.on_update do |path, value|
    #     puts "#{path} was created with #{value}"
    #   end
    def on_create(path, &block)
      (@create_subscribers[path] ||= ThreadSafe::Array.new) << block
    end

    # When an entry is updated the block will be called
    #  Parameters
    #    path
    #      The relative path _excluding_ the root_path to watch for changes
    #    block
    #      The block to be called
    #
    #  Parameters passed to the block:
    #    path
    #      The path that was deleted from doozer
    #
    #    value
    #      New value from doozer
    #
    #    old_value
    #      nil if :cache is false
    #      otherwise the last value for this path in the local copy of the registry
    #
    # Example:
    #   registry.on_update do |path, value, old_value|
    #     puts "#{path} was updated to #{value} with previous value #{old_value}"
    #   end
    #
    # Warning:
    #   If :cache is set to false then on_update will never be called
    #   Every change will go to subscribers of #on_create()
    def on_update(path, &block)
      (@update_subscribers[path] ||= ThreadSafe::Array.new) << block
    end

    # When an entry is deleted the block will be called
    #  Parameters
    #    path
    #      The relative path _excluding_ the root_path to watch for changes
    #    block
    #      The block to be called
    #
    #  Parameters passed to the block:
    #    path
    #      The path that was deleted from doozer
    #
    #    old_value
    #      nil if :cache is false
    #      otherwise the last value for this path in the local copy of the registry
    #
    # Example:
    #   registry.on_delete do |path, old_value|
    #     puts "#{path} was deleted with previous value #{old_value}"
    #   end
    def on_delete(path, &block)
      (@delete_subscribers[path] ||= ThreadSafe::Array.new) << block
    end

    ############################
    protected

    #Subscription = Struct.new(:path, :block, :reg_exp)


    # Returns the full path given a relative path
    def full_path(relative_path)
      "#{@root_path}/#{relative_path}"
    end

    # Returns the full path given a relative path
    def relative_path(full_path)
      full_path.sub(@root_path_with_trail, '')
    end

    # The path has been added or updated in the registry
    def changed(path, value)
      logger.debug { "Changed: #{path} => #{value}" }
      old_value = nil

      # Keeping a local copy of the registry?
      if @registry
        # Already have a value?
        old_value = @registry[path]

        # Update in memory copy
        @registry[path] = value
      end

      if subscribers = old_value ? @update_subscribers[path] : @create_subscribers[path]
        subscribers.each{|subscriber| subscriber.call(path, value, old_value)}
      end
    end

    # Existing data has been removed from the registry
    def deleted(path)
      logger.debug { "Deleted: #{path}" }
      old_value = @registry.delete(path) if @registry
      if subscribers = @delete_subscribers[path]
        subscribers.each{|subscriber| subscriber.call(path, old_value)}
      end
    end

    # Waits for any updates from Doozer and updates the internal service registry
    def watch_registry(watch_path, revision)
      logger.info "Start monitoring #{watch_path}"
      # This thread must use its own dedicated doozer connection
      doozer = RubyDoozer::Client.new(@doozer_config)

      # Watch for any changes
      doozer.watch(watch_path, revision) do |node|
        logger.trace "Registry Change Notification", node

        # Remove the Root path
        path = relative_path(node.path)

        case node.flags
        when 4
          changed(path, node.value)
        when 8
          deleted(path)
        else
          logger.error "Unknown flags returned by doozer:#{node.flags}"
        end
        logger.trace "Updated registry", @registry
      end
      logger.info "Stopping monitoring thread normally"
    rescue Exception => exc
      logger.error "Exception in monitoring thread", exc
    ensure
      doozer.close if doozer
      logger.info "Stopped monitoring for changes in the doozer registry"
    end

  end
end
