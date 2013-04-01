ruby_doozer
===========

Ruby Client calling [doozerd](https://github.com/skynetservices/doozerd)

* http://github.com/skynetservices/ruby_doozer

### Example

```ruby
require 'rubygems'
require 'ruby_doozer'

client = RubyDoozer::Client.new(:server => '127.0.0.1:8046')
client.set('/test/foo', 'value')
result = client.get('/test/foo')
client.close
```

### Logging

Since ruby_doozer uses SemanticLogger, trace level logging of all TCP/IP
calls can be enabled as follows:

```ruby
require 'rubygems'
require 'ruby_doozer'

SemanticLogger::Logger.default_level = :trace
SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('doozer.log')

client = RubyDoozer::Client.new(:server => '127.0.0.1:8046')
client.set('/test/foo', 'value')
result = client.get('/test/foo')
client.close
```

### Registry

RubyDoozer also includes a Registry class to support storing all configuration
information in doozer. This Centralized Configuration allows configuration changes
to be made dynamically at run-time and all interested parties will be notified
of the changes.

For example, making a change to the central database configuration will notify
all application servers to drop their database connections and re-establish them
to the new servers:

```ruby
require 'rubygems'
require 'ruby_doozer'

SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('registry.log')

region      = "Development"
application = "sprites"
path        = "/#{region}/#{application}/config/resources".downcase

config_registry = RubyDoozer::Registry.new(:root_path => path)

# Store the configuration information in doozer as a serialized string
config_registry['master'] = "Some JSON config string"

# Allow time for Doozer to publish the new config
sleep 0.5

# Retrieve the current configuration
database_config = config_registry['master']
slave_database_config = config_registry['secondary']

# Register for any changes to the configuration, including updates
config_registry.on_update('master') do |path, value|
  puts "Time to re-establish database connections to new server: #{value}"
end

# Change the configuration and all subscribers will be notified
config_registry['master'] = "Some updated JSON config string"
```

### Cached Registry

Cached Registry is a specialized registry that keeps a local copy of the entire
registry in memory. It also keeps the local copy synchronized with any changes
that occur in doozer

The local copy is useful for scenarios where frequent reads are being
performed against the Registry and the data must be kept up to date.

Cached Registry can also distinguish between creates and updates.
The new #on_update callbacks will be called when existing data has been modified.
As a result Registry#on_update callbacks will only be called for existing data

```ruby
require 'rubygems'
require 'ruby_doozer'

SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('registry.log')

region      = "Development"
application = "sprites"
path        = "/#{region}/#{application}/config/resources".downcase

config_registry = RubyDoozer::CachedRegistry.new(:root_path => path)

# Store the configuration information in doozer as a serialized string
config_registry['master'] = "Some JSON config string"

# Allow time for Doozer to publish the new config
sleep 0.5

# Retrieve the current configuration
database_config = config_registry['master']
slave_database_config = config_registry['secondary']

# Register for any changes to the configuration
config_registry.on_update('master') do |path, value|
  puts "Time to re-establish database connections to new server: #{value}"
end

# Register for all create events
config_registry.on_create('*') do |path, value|
  puts "CREATED #{path}"
end

# Change the configuration and all subscribers will be notified
config_registry['master'] = "Some updated JSON config string"
```

### Notes

ruby_doozer has been tested against the doozer fork https://github.com/skynetservices/doozerd
which was originally forked from: https://github.com/4ad/doozerd.

### Dependencies

- Ruby MRI 1.8.7 (or above), Ruby 1.9.3,  Or JRuby 1.6.3 (or above)
- [SemanticLogger](http://github.com/ClarityServices/semantic_logger)
- [ResilientSocket](https://github.com/ClarityServices/resilient_socket)
- [ruby_protobuf](https://github.com/macks/ruby-protobuf)
- [multi_json](https://github.com/intridea/multi_json)

### Install

    gem install ruby_doozer

Development
-----------

Want to contribute to Ruby Doozer?

First clone the repo and run the tests:

    git clone git://github.com/skynetservices/ruby_doozer.git
    cd ruby_doozer
    rake test

Feel free to submit an issue and we'll try to resolve it.

Contributing
------------

Once you've made your great commits:

1. [Fork](http://help.github.com/forking/) ruby_doozer
2. Create a topic branch - `git checkout -b my_branch`
3. Push to your branch - `git push origin my_branch`
4. Create an [Issue](http://github.com/skynetservices/ruby_doozer/issues) with a link to your branch
5. That's it!

Meta
----

* Code: `git clone git://github.com/skynetservices/ruby_doozer.git`
* Home: <https://github.com/skynetservices/ruby_doozer>
* Bugs: <http://github.com/skynetservices/ruby_doozer/issues>
* Gems: <http://rubygems.org/gems/ruby_doozer>

This project uses [Semantic Versioning](http://semver.org/).

Authors
-------

Reid Morrison :: reidmo@gmail.com :: @reidmorrison

License
-------

Copyright 2013 Clarity Services, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
