# Policy module for Puppet

[![Puppet Forge](http://img.shields.io/puppetforge/v/raphink/policy.svg)](https://forge.puppetlabs.com/raphink/policy)
[![Build Status](https://travis-ci.org/raphink/puppet-policy.svg?branch=master)](https://travis-ci.org/raphink/puppet-policy)
[![Coverage Status](https://img.shields.io/coveralls/raphink/puppet-policy.svg)](https://coveralls.io/r/raphink/puppet-policy)


**Your Policy Driven Infrastructure Starter Kit**


## Requirements

This module requires the following Ruby gems:

* `rspec`;
* [`rspec-puppet`](https://github.com/rodjek/rspec-puppet) for catalog tests;
* [`serverspec`](https://github.com/mizzy/serverspec) (&gt;= 2.0.0) for functional tests.

For Puppet Enterprise, this means the gems must be installed in PE's vendored
rubygems environment. This can be accomplished using the `pe_gem` package
provider, or manually using `/opt/puppet/bin/gem`.


## Installing

The policy module should be copied to the `modulepath` which generates
catalogs for the puppet master. Pluginsync will ensure it is installed at the
master's next puppet run.

Next, routes.yaml must be configured to use the termini of your choice. See the sections below for details of how to configure routes.yaml.


## Catalog policies

This module provides a new Puppet terminus which allows to evaluate rspec tests on the actual compiled catalog.

In order to use this terminus:

* Run Puppet with `pluginsync` on the Puppet master to copy the indirectors;
* Set your `$confdir/routes.yaml` to use the terminus:

        master:
          catalog:
            terminus: compiler_spec
* Restart your Puppet master process

### How it works

The catalog policy compiler, though it replaces the built in compiler, does not compile
catalogs on its own. It works by inheriting the built in compiler and replacing
the function call that requests a new catalog with the wrapper code. The process
essentially looks like this:

  When a catalog is requested:
  1. Call the built in compiler
  2. Extract all facter data from the compiled catalog
  3. Pass the catalog to RSpec along with a `facts` hash with all facts
  4. Call every *_spec.rb file in `$manifestdir/../policy` that are in a directory matching a declared class
  5. Fail the catalog if any of the tests fail


The `compiler_spec` terminus extends the `compiler` terminus for catalogs. After retrieving the catalog using the `compiler` terminus, it applies rspec tests to it:

* The rspec tests must be located in `:manifestdir/../policy/catalog/class`, in sub-directories by class;
* Only the directories named after classes declared in the catalog will be tested;
* `rspec-puppet` matchers are already loaded, so they are available in tests;
* the catalog is readily available in the tests, along with a `facts` object.

Sample output:

    # puppet agent -t

    info: Retrieving plugin
    Error: Could not retrieve catalog from remote server: Error 400 on SERVER: Catalog failed to pass security policies:
    -- Failed policy: expected that the catalogue would contain Package[pe-mcollective]
    -- Failed policy: expected that the catalogue would not contain Service[pe-mcollective]
    notice: Using cached catalog

### Writing tests

All files in `$manifestdir/../policy` that end with `_spec.rb` and are located
in a directory matching a declared class name will be executed by
the policy compiler. Any Ruby, RSpec, or rspec-puppet code is valid in these
files.

Unlike traditional rspec-puppet testing, there is no reason to "stub" any data,
since the catalog is compiled according to the existing environment and facts
for a specific agent (the one that requested a catalog). Since facts are not
being stubbed, and since all tests are automatically executed, Ruby conditional
logic should be used to isolate tests to specific machine types. For example:

```ruby
# security_spec.rb

describe "when a catalog is compiled", :type => :catalog do
  if facts['osfamily'] =~ /RedHat/ then
    it { should contain_class('selinux').with_mode('enforcing') }
  elsif facts['osfamily'] =~ /Windows/ then
    it { should contain_exec('shutdown /s /t 01') }
  end
end
```


## Server policies

After the catalog has been tested and applied, you might want to run functional tests against the machine. This module provides a `rest_spec` terminus for the report indirector which executes rspec tests using the `serverspec` matchers.

In order to use it:

* The rspec tests must be located in `:vardir/policy/server` (tests can be deployed using the `policy::serverspec` define);
* `serverspec` matchers are already loaded, so they are available in tests.

To activate the terminus, you need set it in `$confdir/routes.yaml`:

    agent:
      report:
        terminus: rest_spec

This indirector will automatically generate serverspec tests from the catalog for known resource types, making the catalog self-asserting. Currently, it supports the following resource types:

* Package
* Service
* File
* User

Sample output:

    # puppet agent  -t
    info: Retrieving plugin
    info: Caching catalog for foo.example.com
    info: Applying configuration version 'raphink/a2c8e0f [+]'
    ... Applying changes ...
    notice: Finished catalog run in 59.19 seconds
    err: Could not send report: Unit tests failed:
    FF
    
    Failures:
    
      1) augeas 
         Failure/Error: it { should be_installed }
           expected "augeas" to be installed
         # /var/lib/puppet/policy/server/package_spec.rb:2
         # /var/lib/puppet/lib/puppet/indirector/report/rest_spec.rb:45:in `save'
    
      2) /usr/share/augeas/lenses/dist 
         Failure/Error: it { should be_file }
           expected "/usr/share/augeas/lenses/dist" to be file
         # /var/lib/puppet/policy/server/package_spec.rb:6
         # /var/lib/puppet/lib/puppet/indirector/report/rest_spec.rb:45:in `save'
    
    Finished in 0.06033 seconds
    2 examples, 2 failures
    
    Failed examples:
    
    rspec /var/lib/puppet/policy/server/package_spec.rb:2 # augeas 
    rspec /var/lib/puppet/policy/server/package_spec.rb:6 # /usr/share/augeas/lenses/dist 


### Writing new automatic serverspec plugins

The `rest_spec` report terminus automatically generates serverspec test files from the Puppet catalog, by mapping Puppet resources to Serverspec resources.

New plugins need to be distributed using `pluginsync`. They should be placed in the `lib/puppetx/policy/auto_spec` directory.

Here is an example:

```ruby
Puppetx::Policy::AutoSpec.newspec 'Openldap_database' do |o|
  should = (o[:ensure] == 'absent') ? 'should_not' : 'should'
  content = "  describe command('ldapsearch -LLL -x -b #{o[:suffix]}') do\n"
  content += "    its(:stdout) { #{should} match /dn: #{o[:suffix]}/ }\n"
  content += "  end\n"
end
```

It also works with defined resource types:

```ruby
Puppetx::Policy::AutoSpec.newspec 'Apache::Vhost' do |v|
  should = (p[:ensure] == 'absent') ? 'should_not' : 'should'
  "  describe port('#{v[:port]}') do\n     it { #{should} be_listening }\n  end\n" if v[:port]
end
```


## Using the MCollective agent

This module provides an MCollective agent in `files/mcollective/agent`. This agent currently has two actions:

### Documentation

    $ mco plugin doc spec
    RSpec tests
    ===========
    
    RSpec tests
    
          Author: Raphaël Pinson
         Version: 0.1
         License: GPLv3
         Timeout: 60
       Home Page: 
    
    ACTIONS:
    ========
       check, run
    
       check action:
       -------------
           Run a check with the serverspec library
    
           INPUT:
               action:
                  Description:
                       Prompt: Action to check
                         Type: string
                   Validation: ^\S+$
                       Length: 50

               type:
                  Description:
                       Prompt: Type of resource
                         Type: string
                     Optional: false
                   Validation: ^\S+$
                       Length: 50
    
               values:
                  Description:
                       Prompt: Values to check
                         Type: string
                   Validation: ^\S+$
                       Length: 100
    
    
           OUTPUT:
               passed:
                  Description: Whether the checked passed
                   Display As: Passed
    
       run action:
       -----------
           Run Puppet-policy server tests
    
           INPUT:
    
           OUTPUT:
               output:
                  Description: Output of tests
                   Display As: Output
    
               passed:
                  Description: Whether the tests passed
                   Display As: Passed

### Examples

Using the `check` action:

    $ mco rpc spec check type=service action=running values=ssh
    Discovering hosts using the mc method for 2 second(s) .... 1
    
     * [ ============================================================> ] 1 / 1
    
    
    wrk4                                     
       Passed: true

    
    Finished processing 1 / 1 hosts in 373.44 ms


Using the `run` action:

    $ mco rpc spec run 
    Discovering hosts using the mc method for 2 second(s) .... 1
    
     * [ ============================================================> ] 1 / 1
    
    wrk4                                     
       Output: F
               
               Failures:
               
                 1) abc 
                    Failure/Error: it { should be_running }
                      expected "abc" to be running
                    # /var/lib/puppet/policy/server/my_test_spec.rb:3
                    # /usr/share/mcollective/plugins/mcollective/agent/spec.rb:75:in `run_action'
               
               Finished in 0.00926 seconds
               1 example, 1 failure
               
               Failed examples:
               
               rspec /var/lib/puppet/policy/server/my_test_spec.rb:3 # abc 
       Passed: false


    Finished processing 1 / 1 hosts in 316.46 ms


## Contributing

Please report bugs and feature request using [GitHub issue
tracker](https://github.com/raphink/puppet-policy/issues).

For pull requests, it is very much appreciated to check your Puppet manifest
with [puppet-lint](https://github.com/raphink/puppet-policy/issues) to follow the recommended Puppet style guidelines from the
[Puppet Labs style guide](http://docs.puppetlabs.com/guides/style_guide.html).

## License

Copyright (c) 2013-2014 Raphaël Pinson

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    
    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

