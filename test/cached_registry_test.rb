# Allow test to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../lib'

require 'rubygems'
require 'test/unit'
require 'shoulda'
require 'ruby_doozer'

# NOTE:
# This test assumes that doozerd is running locally on the default port of 8046

# Register an appender if one is not already registered
if SemanticLogger::Logger.appenders.size == 0
  SemanticLogger::Logger.default_level = :trace
  SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('test.log')
end

# Unit Test for RubyDoozer::Client
class CachedRegistryTest < Test::Unit::TestCase
  context RubyDoozer::CachedRegistry do
    context "with test data" do
      setup do
        @test_data = {
          'bar' => 'test',
          'one' => 'one',
          'two' => 'two',
        }
        # Doozer does not allow '_' in path names
        @root_path = "/registrytest"
        @registry = RubyDoozer::CachedRegistry.new(:root_path => @root_path)
        @test_data.each_pair {|k,v| @registry[k] = v}
        # Give doozer time to send back the changes
        sleep 0.5
      end

      def teardown
        if @registry
          @test_data.each_pair {|k,v| @registry.delete(k)}
          @registry.delete('three')
          @registry.finalize
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
        # Give doozer time to send back the change
        sleep 0.5
        result = @registry['three']
        assert_equal 'value', result
      end

      [nil, '*'].each do |monitor_path|
        context "with monitor_path:#{monitor_path}" do
          should "callback on create" do
            created_path = nil
            created_value = nil
            @registry.on_create(monitor_path||'three') do |path, value|
              created_path = path
              created_value = value
            end
            @registry['three'] = 'created'
            # Allow doozer to send back the change
            sleep 0.5
            assert_equal 'three', created_path
            assert_equal 'created', created_value
          end

          should "callback on update" do
            updated_path = nil
            updated_value = nil
            @registry.on_update(monitor_path||'bar') do |path, value|
              updated_path = path
              updated_value = value
            end
            @registry['bar'] = 'updated'
            # Allow doozer to send back the change
            sleep 0.5
            assert_equal 'bar', updated_path
            assert_equal 'updated', updated_value
          end

          should "callback on delete" do
            deleted_path = nil
            @registry.on_delete(monitor_path||'bar') do |path|
              deleted_path = path
            end
            # Allow doozer to send back the change
            @registry.delete('bar')
            sleep 0.5
            assert_equal 'bar', deleted_path
          end
        end
      end

      ['other', 'one'].each do |monitor_path|
        context "with monitor_path:#{monitor_path}" do
          should "not callback on create" do
            created_path = nil
            created_value = nil
            @registry.on_create(monitor_path) do |path, value|
              created_path = path
              created_value = value
            end
            @registry['three'] = 'created'
            # Allow doozer to send back the change
            sleep 0.5
            assert_equal nil, created_path
            assert_equal nil, created_value
          end

          should "not callback on update" do
            updated_path = nil
            updated_value = nil
            @registry.on_update(monitor_path) do |path, value|
              updated_path = path
              updated_value = value
            end
            @registry['bar'] = 'updated'
            # Give doozer time to send back the change
            sleep 0.5
            assert_equal nil, updated_path
            assert_equal nil, updated_value
          end

          should "not callback on delete" do
            deleted_path = nil
            @registry.on_delete(monitor_path) do |path|
              deleted_path = path
            end
            @registry.delete('bar')
            # Give doozer time to send back the change
            sleep 0.5
            assert_equal nil, deleted_path
          end
        end
      end
    end

  end
end