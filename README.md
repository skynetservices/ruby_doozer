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

Since ruby_skynet uses SemanticLogger, trace level logging of all TCP/IP
calls can be enabled as follows:

```ruby
require 'rubygems'
require 'ruby_skynet'

SemanticLogger::Logger.default_level = :trace
SemanticLogger::Logger.appenders << SemanticLogger::Appender::File.new('skynet.log')

class EchoService
  include RubySkynet::Base
end

client = EchoService.new
p client.echo(:hello => 'world')
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
