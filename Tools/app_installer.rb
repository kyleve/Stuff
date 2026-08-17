# frozen_string_literal: true

require "fileutils"
require "open3"
require "optparse"
require "tmpdir"

require_relative "file_transaction"

# Finds only processes whose argv executable is the installed app binary.
class InstalledProcessTable
  def self.pids(output:, executable:)
    output.lines.filter_map do |line|
      match = line.match(/^\s*(\d+)\s+(.+?)\s*$/)
      next unless match

      command = match[2]
      match[1].to_i if command == executable || command.start_with?("#{executable} ")
    end
  end
end

# Validates and transactionally replaces one installed macOS app bundle.
class AppInstaller
  class Error < StandardError; end

  def initialize(app_name:, bundle_id:, transaction_factory:)
    @app_name = app_name
    @bundle_id = bundle_id
    @transaction_factory = transaction_factory
  end

  def validate_destination(destination)
    raise Error, "installation destination must be absolute: #{destination}" unless destination.start_with?(File::SEPARATOR)

    destination = File.expand_path(destination)
    expected_basename = "#{@app_name}.app"
    raise Error, "installation destination must end in #{expected_basename}: #{destination}" unless File.basename(destination) == expected_basename

    parent = File.dirname(destination)
    raise Error, "installation destination directory does not exist: #{parent}" unless Dir.exist?(parent)
    raise Error, "installation destination directory is a symlink: #{parent}" if File.symlink?(parent)
    if File.symlink?(destination)
      raise Error, "refusing to replace a symlink at #{destination}"
    end
    if File.exist?(destination)
      raise Error, "refusing to replace a non-directory at #{destination}" unless Dir.exist?(destination)
      validate_app(destination)
    end
    destination
  end

  def validate_app(app)
    raise Error, "app bundle does not exist: #{app}" unless Dir.exist?(app)

    info = File.join(app, "Contents", "Info.plist")
    raise Error, "app bundle has no Contents/Info.plist: #{app}" unless File.file?(info)

    output, error, status = Open3.capture3(
      "/usr/bin/plutil",
      "-extract",
      "CFBundleIdentifier",
      "raw",
      "-o",
      "-",
      info,
    )
    unless status.success?
      detail = error.strip.empty? ? "plutil exited #{status.exitstatus}" : error.strip
      raise Error, "couldn't read #{info}: #{detail}"
    end
    actual = output.strip
    raise Error, "refusing app bundle #{app}; bundle identifier is #{actual.inspect}, expected #{@bundle_id.inspect}" unless actual == @bundle_id

    app
  end

  def install(source:, destination:)
    source = File.expand_path(source)
    destination = validate_destination(destination)
    validate_app(source)

    Dir.mktmpdir(".#{@app_name}.install-", File.dirname(destination)) do |stage|
      staged_app = File.join(stage, "#{@app_name}.app")
      FileUtils.copy_entry(source, staged_app, true, false)
      validate_app(staged_app)
      transaction = @transaction_factory.call
      transaction.replace(target: destination, staged: staged_app)
      transaction.commit
    end
  rescue SystemCallError => error
    raise Error, "can't install to #{destination}: #{error.message}"
  end
end

def app_installer_main(arguments)
  command = arguments.shift
  options = {}
  parser = OptionParser.new do |flags|
    flags.on("--app-name NAME") { |value| options[:app_name] = value }
    flags.on("--bundle-id ID") { |value| options[:bundle_id] = value }
    flags.on("--destination PATH") { |value| options[:destination] = value }
    flags.on("--source PATH") { |value| options[:source] = value }
    flags.on("--executable PATH") { |value| options[:executable] = value }
  end
  parser.parse!(arguments)

  case command
  when "pids"
    puts InstalledProcessTable.pids(output: $stdin.read, executable: options.fetch(:executable))
  when "validate-destination"
    installer(options).validate_destination(options.fetch(:destination))
  when "validate-app"
    installer(options).validate_app(options.fetch(:source))
  when "install"
    installer(options).install(source: options.fetch(:source), destination: options.fetch(:destination))
  else
    raise AppInstaller::Error, "unknown app installer command: #{command || '(none)'}"
  end
  0
rescue AppInstaller::Error, FileTransaction::CleanupError, KeyError, OptionParser::ParseError => error
  warn "error: #{error.message}"
  1
end

def installer(options)
  AppInstaller.new(
    app_name: options.fetch(:app_name),
    bundle_id: options.fetch(:bundle_id),
    transaction_factory: -> { FileTransaction.new },
  )
end

exit(app_installer_main(ARGV)) if __FILE__ == $PROGRAM_NAME
