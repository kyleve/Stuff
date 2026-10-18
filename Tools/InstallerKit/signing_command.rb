# frozen_string_literal: true

require 'optparse'
require 'json'
require_relative '../repository'

module InstallerSigning
  # Public arguments are parsed before tools or credentials are accessed.
  module Command
    ROOT_DIRECTORY = Repository.root(__FILE__)

    def self.run(argv)
      options = { 'source' => ROOT_DIRECTORY }
      command = argv.shift
      parser = OptionParser.new do |p|
        p.banner = 'Usage: ./signing refresh|register-device|archive --app APP [options]'
        p.on('--app APP', 'Registered iOS app') { |v| options['app'] = v }
        p.on('--source DIR', 'Source checkout (defaults to this checkout)') { |v| options['source'] = File.expand_path(v) }
        p.on('--output DIR', 'New archive output directory') { |v| options['output'] = File.expand_path(v) }
        p.on('--name NAME', 'Device name for register-device') { |v| options['name'] = v }
        p.on('--udid UDID', 'Device UDID for register-device') { |v| options['udid'] = v }
        p.on('-h', '--help') { puts p; return 0 }
      end
      if %w[-h --help].include?(command)
        puts parser
        return 0
      end
      parser.parse!(argv)
      raise ArgumentError, 'Unexpected positional arguments' unless argv.empty?
      raise ArgumentError, 'Expected refresh, register-device, or archive' unless %w[refresh register-device archive].include?(command)
      apps = JSON.parse(File.read(File.join(__dir__, 'signing_apps.json')))
      raise ArgumentError, 'Select a registered app with --app' unless apps.key?(options['app'])
      raise ArgumentError, 'Source directory does not contain ide' unless File.file?(File.join(options['source'], 'ide'))
      if command == 'archive'
        raise ArgumentError, '--output is required' unless options['output']
        raise ArgumentError, 'Output directory already exists' if File.exist?(options['output']) || File.symlink?(options['output'])
      elsif options['output']
        raise ArgumentError, '--output is only valid for archive'
      end
      if command == 'register-device'
        raise ArgumentError, '--name and --udid are required' unless options['name'] && !options['name'].strip.empty? && options['udid']
        raise ArgumentError, 'Invalid device UDID' unless /\A(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})\z/.match?(options['udid'])
      elsif options['name'] || options['udid']
        raise ArgumentError, '--name and --udid are only valid for register-device'
      end
      if command != 'archive' && (ENV['CI'] || ENV['CIRCLECI'])
        raise ArgumentError, 'Signing maintenance is local only'
      end
      Dir.chdir(ROOT_DIRECTORY) do
        environment = { 'BUNDLE_GEMFILE' => File.join(ROOT_DIRECTORY, 'Gemfile'), 'BUNDLE_FROZEN' => 'true',
                        'BUNDLE_PATH' => File.join(ROOT_DIRECTORY, 'vendor/bundle'),
                        'FASTLANE_SKIP_UPDATE_CHECK' => '1', 'FASTLANE_OPT_OUT_USAGE' => '1' }
        unless system(environment, 'mise', 'exec', '--', 'bundle', 'check', out: File::NULL)
          warn 'error: Locked Fastlane dependencies are missing. Run ./ide --install --no-open.'
          return 1
        end
        exec(environment, 'mise', 'exec', '--', 'bundle', 'exec', 'fastlane', (command == 'register-device' ? 'register_install_device' : command),
             *options.map { |key, value| "#{key}:#{value}" })
      end
    rescue OptionParser::ParseError, ArgumentError, SystemCallError => e
      warn "error: #{e.message}"
      1
    end
  end
end

exit InstallerSigning::Command.run(ARGV) if $PROGRAM_NAME == __FILE__
