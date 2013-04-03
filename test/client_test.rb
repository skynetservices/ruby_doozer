# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'ruby_doozer/client'

# NOTE:
# This test assumes that doozerd is running locally on the default port of 8046

# Register an appender if one is not already registered
SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log') if SemanticLogger.appenders.size == 0

# Unit Test for RubyDoozer::Client
class ClientTest < Test::Unit::TestCase
  context RubyDoozer::Client do

    context "without server" do
      should "raise exception when cannot reach doozer server after 5 retries" do
        exception = assert_raise ResilientSocket::ConnectionFailure do
          RubyDoozer::Client.new(
            # Bad server address to test exception is raised
            :server                 => 'localhost:9999',
            :connect_retry_interval => 0.1,
            :connect_retry_count    => 5)
        end
        assert_match /After 5 connection attempts to host 'localhost:9999': Errno::ECONNREFUSED/, exception.message
      end

    end

    context "with client connection" do
      PATHS = ['/test/foo', '/test/with_underscores', '/test/deeper_one/and_again_with_multiple']

      setup do
        @client = RubyDoozer::Client.new(:server => 'localhost:8046')
      end

      def teardown
        if @client
          @client.close
          PATHS.each {|path| @client.delete(path)}
        end
      end

      should "return current revision" do
        assert @client.current_revision >= 0
      end

      should "return nil when a key is not found" do
        assert_equal nil, @client['/test/some_bad_key']
      end

      context "successfully set and get data" do
        PATHS.each do |path|
          should "in #{path}" do
            new_revision = @client.set(path, 'value')
            result = @client.get(path)
            assert_equal 'value', result.value
            assert_equal new_revision, result.rev
          end

          should "successfully set and get data using array operators in #{path}" do
            @client[path] = 'value2'
            result = @client[path]
            assert_equal 'value2', result
          end
        end
      end

      context "with a directory tree" do
        setup do
          PATHS.each {|path| @client[path] = path}
        end

        should "walk" do
          # Fetch all the configuration information from Doozer and set the internal copy
          count = 0
          @client.walk('/test/**') do |path, value, revision|
            assert_equal true, PATHS.include?(path)
            assert_equal path, value
            count += 1
          end
          assert_equal PATHS.size, count
        end
      end

      should "fetch directories in a path" do
        @path = '/'
        count = 0
        until @client.directory(@path, count).nil?
          count += 1
        end
        assert count > 0
      end

    end
  end
end