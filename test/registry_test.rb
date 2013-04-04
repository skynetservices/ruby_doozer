# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'ruby_doozer'

# NOTE:
# This test assumes that doozerd is running locally on the default port of 8046

# Register an appender if one is not already registered
SemanticLogger.default_level = :trace
SemanticLogger.add_appender('test.log') if SemanticLogger.appenders.size == 0

# Unit Test for RubyDoozer::Client
class RegistryTest < Test::Unit::TestCase
  context RubyDoozer::Registry do
    context "with test data" do
      setup do
        @test_data = {
          'bar' => 'test',
          'one' => 'one',
          'two' => 'two',
        }
        # Doozer does not allow '_' in path names
        @root_path = "/registrytest"
        @client = RubyDoozer::Client.new(:server => 'localhost:8046')
        @test_data.each_pair {|k,v| @client.set("#{@root_path}/#{k}",v)}

        @registry = RubyDoozer::Registry.new(:root_path => @root_path)
      end

      def teardown
        @registry.finalize if @registry
        if @client
          @test_data.each_pair do |k,v|
            @client.delete("#{@root_path}/#{k}")
          end
          @client.delete("#{@root_path}/three")
          @client.close
        end
      end

      should "have complete registry" do
        @test_data.each_pair do |k,v|
          assert_equal v, @registry[k], "Expected #{k}=>#{v}, #{@registry.to_h.inspect}"
        end
      end

      should "iterate over complete registry" do
        @registry.each_pair do |k,v|
          assert_equal v, @test_data[k], "Registry #{k}=>#{v}, #{@registry.to_h.inspect}"
        end
      end

      should "successfully set and retrieve data" do
        @registry['three'] = 'value'
        # Allow doozer to send back the change
        sleep 0.3
        result = @registry['three']
        assert_equal 'value', result
      end

      [nil, '*'].each do |monitor_path|
        context "with monitor_path:#{monitor_path}" do
          should "callback on update" do
            updated_revision = nil
            updated_path = nil
            updated_value = nil
            @registry.on_update(monitor_path||'bar') do |path, value, revision|
              updated_revision = revision
              updated_path = path
              updated_value = value
            end
            # Allow monitoring thread to start
            sleep 0.1
            @registry['bar'] = 'updated'
            # Allow doozer to send back the change
            sleep 0.3
            assert_equal 'bar', updated_path
            assert_equal 'updated', updated_value
            assert_equal true, updated_revision > 0
          end

          should "callback on delete" do
            deleted_path = nil
            deleted_revision = nil
            @registry.on_delete(monitor_path||'bar') do |path, revision|
              deleted_path = path
              deleted_revision = revision
            end
            # Allow monitoring thread to start
            sleep 0.1
            # Allow doozer to send back the change
            @registry.delete('bar')
            sleep 0.3
            assert_equal 'bar', deleted_path
            assert_equal true, deleted_revision > 0
          end
        end
      end

      ['other', 'one'].each do |monitor_path|
        context "with monitor_path:#{monitor_path}" do
          should "not callback on update" do
            updated_path = nil
            updated_value = nil
            @registry.on_update(monitor_path) do |path, value|
              updated_path = path
              updated_value = value
            end
            # Allow monitoring thread to start
            sleep 0.1
            @registry['bar'] = 'updated'
            # Allow doozer to send back the change
            sleep 0.3
            assert_equal nil, updated_path
            assert_equal nil, updated_value
          end

          should "not callback on delete" do
            deleted_path = nil
            @registry.on_delete(monitor_path) do |path|
              deleted_path = path
            end
            # Allow monitoring thread to start
            sleep 0.1
            # Allow doozer to send back the change
            @registry.delete('bar')
            sleep 0.3
            assert_equal nil, deleted_path
          end
        end
      end

    end
  end
end