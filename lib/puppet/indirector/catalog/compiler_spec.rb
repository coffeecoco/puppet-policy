require 'puppet/node'
require 'puppet/indirector/catalog/compiler'
require 'rspec'
require 'rspec-puppet/errors'
require 'rspec-puppet/matchers'
require 'rspec/core/formatters/json_formatter'

## RSpec catalog helper module to provide `subject` method for specs
module RSpec::Puppet::CatalogExampleGroup
  include RSpec::Puppet::ManifestMatchers

  def subject
    RSpec.configuration.catalog
  end

  def facts
    RSpec.configuration.facts
  end
end

class Puppet::Resource::Catalog::CompilerSpec < Puppet::Resource::Catalog::Compiler
  desc "Puppet's catalog policy enforcement compiler"

  def find(request)
    ## Call normal catalog compiler and grab the facts
    catalog = super
    facts = Puppet::Node::Facts.convert_from(request.options[:facts_format], CGI.unescape(request.options[:facts])).values

    # We put specs in the parent directory of :manifestdir
    node = node_from_request(request)
    manifest = Puppet.settings.value(:manifest)
#    spec_dir = File.join(manifest, '../policy/catalog')
    spec_dir = File.join('/etc/puppetlabs/code/environments/m/policy/catalog/')

    # Test by classes, including $certname
     spec_dirs = ['/etc/puppetlabs/code/environments/m/policy/catalog/']
#    spec_dirs = []
    catalog.classes.each do |c|
      class_dir = c.gsub(/:/, '_')
      class_path = File.join(spec_dir, "class/#{class_dir}")
      spec_dirs << class_path if File.directory? class_path
    end

    ## Check policy failures and return catalog if there were no failures
    if (failed_policies = policy_check(catalog, facts, spec_dirs)).empty?
      catalog
    else
      raise Puppet::Error, "Catalog failed to pass security policies:\n" + failed_policies.join("\n")
    end
  end

  def policy_check(catalog, facts, dirs)
    ## Configure RSpec with catalog spec helper and compiled catalog data
    RSpec.configuration.color = true
    RSpec.configure do |c|
      c.add_formatter(:progress)
      c.add_formatter(:json)
      c.add_setting :catalog, :default => catalog
      c.add_setting :facts,   :default => facts
      c.backtrace_exclusion_patterns = [
        /\/puppet\/(lib|bin)\//,
        /\/ruby\//,
      ]
      c.include RSpec::Puppet::CatalogExampleGroup
      c.extend  RSpec::Puppet::CatalogExampleGroup
    end

    ## Configure JSON RSpec reporting formatter
    config = RSpec.configuration
#    progress_formatter = RSpec::Core::Formatters::ProgressFormatter.new($stdout)
    formatter = RSpec::Core::Formatters::JsonFormatter.new(config.output_stream)
    reporter  = RSpec::Core::Reporter.new(config)
    config.instance_variable_set(:@reporter, reporter)

loader = config.send(:formatter_loader)
notifications = loader.send(:notifications_for, RSpec::Core::Formatters::JsonFormatter)
reporter.register_listener(formatter, *notifications)

    ## Run RSpec on the policies directory
    Puppet.info("Performing policy rspec-puppet checks")


RSpec::Core::Runner.disable_autorun!

    RSpec::Core::Runner.run(dirs)
RSpec.instance_variable_set("@world",nil)
RSpec.instance_variable_set("@configuration",nil)

    ## Return an array of failed policy descriptions
    formatter.output_hash[:examples].collect do |policy|
      "-- Failed policy: #{policy[:exception][:message]}" if policy[:status] == 'failed'

    end.compact

  end
end
