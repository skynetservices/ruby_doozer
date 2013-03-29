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

      # Run tests with and without a local cache
      [true, false].each do |cache|
        context "cache:#{cache}" do
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
            sleep 0.5
            result = @registry['three']
            assert_equal 'value', result
          end

          should "invoke callbacks on create" do
            created_path = nil
            created_value = nil
            @registry.on_create('three') do |path, value|
              created_path = path
              created_value = value
            end
            @registry['three'] = 'created'
            # Allow doozer to send back the change
            sleep 0.5
            assert_equal 'three', created_path
            assert_equal 'created', created_value
          end

          should "invoke callbacks on update" do
            # Update only triggers when the cache is enabled
            if cache
              updated_path = nil
              updated_value = nil
              @registry.on_update('bar') do |path, value|
                updated_path = path
                updated_value = value
              end
              @registry['bar'] = 'updated'
              # Allow doozer to send back the change
              sleep 0.5
              assert_equal 'bar', updated_path
              assert_equal 'updated', updated_value
            end
          end

          should "invoke callbacks on delete" do
            deleted_path = nil
            deleted_value = nil
            @registry.on_delete('bar') do |path, old_value|
              deleted_path = path
              deleted_value = old_value
            end
            # Allow doozer to send back the change
            @registry.delete('bar')
            sleep 0.5
            assert_equal 'bar', deleted_path
            assert_equal 'test', deleted_value
          end

        end
      end

    end
  end
end