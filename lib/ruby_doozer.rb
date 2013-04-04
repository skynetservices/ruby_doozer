require 'semantic_logger'

module RubyDoozer
  autoload :Client,         'ruby_doozer/client'
  autoload :Registry,       'ruby_doozer/registry'
  autoload :CachedRegistry, 'ruby_doozer/cached_registry'
  module Json
    autoload :Serializer,   'ruby_doozer/json/serializer'
    autoload :Deserializer, 'ruby_doozer/json/deserializer'
  end
end
