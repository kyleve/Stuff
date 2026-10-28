# frozen_string_literal: true

require "fileutils"
require "json"
require "optparse"
require "tempfile"

# Owns the durable checkout-to-simulator claim and validates it against simctl.
class SimulatorRegistry
  Entry = Struct.new(:checkout, :udid, :device, :os, keyword_init: true)
  Resolution = Struct.new(:action, :udid, keyword_init: true)

  def initialize(directory:)
    @directory = File.expand_path(directory)
  end

  def resolve(name:, checkout:, device:, os:, runtime_key:, all:, available:)
    entry = load_entry(name)
    missing_registered_udid = nil
    if entry
      validate_metadata(entry, checkout: checkout, device: device, os: os, name: name)
      exact = inventory_device(all, runtime_key: runtime_key, udid: entry.udid, name: name)
      if exact
        unless inventory_device(available, runtime_key: runtime_key, udid: entry.udid, name: name)
          raise "registered device #{entry.udid} exists but is not available on #{runtime_key}"
        end
        return Resolution.new(action: "owned", udid: entry.udid)
      end
      if inventory_udids(all).include?(entry.udid)
        raise "registry entry #{name} points to #{entry.udid}, but that device has a different name or runtime"
      end
      missing_registered_udid = entry.udid
    end

    available_matches = named_udids(available, runtime_key: runtime_key, name: name)
    if missing_registered_udid && available_matches.any?
      raise "registered device #{missing_registered_udid} is gone; refusing to replace its claim with #{available_matches.join(', ')}"
    end
    if available_matches.length > 1
      raise "several unclaimed '#{name}' devices exist on #{runtime_key}; refusing to choose one"
    end
    return Resolution.new(action: "claim", udid: available_matches.first) if available_matches.one?

    all_matches = named_udids(all, runtime_key: runtime_key, name: name)
    if all_matches.any?
      raise "unclaimed '#{name}' exists on #{runtime_key}, but it is not available"
    end

    Resolution.new(action: "create", udid: nil)
  end

  def deletion_target(name:, checkout:, device:, os:, runtime_key:, all:)
    entry = load_entry(name)
    unless entry
      matches = named_udids(all, runtime_key: runtime_key, name: name)
      if matches.any?
        raise "refusing to delete unowned '#{name}' on #{runtime_key}; the registry has no claim"
      end
      return Resolution.new(action: "none", udid: nil)
    end

    validate_metadata(entry, checkout: checkout, device: device, os: os, name: name)
    exact = inventory_device(all, runtime_key: runtime_key, udid: entry.udid, name: name)
    return Resolution.new(action: "delete", udid: entry.udid) if exact

    if inventory_udids(all).include?(entry.udid)
      raise "refusing to delete #{entry.udid}; it no longer matches '#{name}' on #{runtime_key}"
    end
    matches = named_udids(all, runtime_key: runtime_key, name: name)
    if matches.any?
      raise "registered device #{entry.udid} is gone; refusing to delete or claim matching unowned device(s): #{matches.join(', ')}"
    end
    Resolution.new(action: "stale", udid: nil)
  end

  def prune_target(name:, runtime_key:, all:)
    entry = load_entry(name)
    return Resolution.new(action: "none", udid: nil) unless entry

    exact = inventory_device(all, runtime_key: runtime_key, udid: entry.udid, name: name)
    return Resolution.new(action: "delete", udid: entry.udid) if exact
    return Resolution.new(action: "stale", udid: nil) unless inventory_udids(all).include?(entry.udid)

    raise "refusing to prune #{entry.udid}; registry entry #{name} does not match that device's name and runtime"
  end

  def record(name:, checkout:, udid:, device:, os:)
    validate_name(name)
    FileUtils.mkdir_p(@directory, mode: 0o700)
    File.chmod(0o700, @directory)
    Tempfile.create([".#{name}.", ".tmp"], @directory) do |file|
      file.chmod(0o600)
      file.write("checkout=#{checkout}\nudid=#{udid}\ndevice=#{device}\nos=#{os}\n")
      file.flush
      file.fsync
      File.rename(file.path, entry_path(name))
    end
  end

  def forget(name)
    validate_name(name)
    File.unlink(entry_path(name))
  rescue Errno::ENOENT
    nil
  end

  def load_entry(name)
    validate_name(name)
    path = entry_path(name)
    return nil unless File.file?(path)

    fields = File.readlines(path, chomp: true).to_h do |line|
      key, value = line.split("=", 2)
      [key, value]
    end
    missing = %w[checkout udid device os].reject { |key| fields[key] && !fields[key].empty? }
    raise "registry entry #{name} is missing #{missing.join(', ')}" unless missing.empty?

    Entry.new(
      checkout: fields.fetch("checkout"),
      udid: fields.fetch("udid"),
      device: fields.fetch("device"),
      os: fields.fetch("os"),
    )
  end

  private

  def validate_metadata(entry, checkout:, device:, os:, name:)
    return if entry.checkout == checkout && entry.device == device && entry.os == os

    raise "registry entry #{name} belongs to #{entry.checkout} (#{entry.device} / iOS #{entry.os}), not #{checkout} (#{device} / iOS #{os})"
  end

  def validate_name(name)
    raise "invalid registry name #{name.inspect}" if name.empty? || name.include?(File::SEPARATOR) || [".", ".."].include?(name)
  end

  def entry_path(name)
    File.join(@directory, name)
  end

  def devices(inventory, runtime_key)
    inventory.fetch("devices", {}).fetch(runtime_key, [])
  end

  def named_udids(inventory, runtime_key:, name:)
    devices(inventory, runtime_key).filter_map do |candidate|
      candidate["udid"] if candidate["name"] == name
    end
  end

  def inventory_device(inventory, runtime_key:, udid:, name:)
    devices(inventory, runtime_key).find do |candidate|
      candidate["udid"] == udid && candidate["name"] == name
    end
  end

  def inventory_udids(inventory)
    inventory.fetch("devices", {}).values.flatten.filter_map { |candidate| candidate["udid"] }
  end
end

def simulator_registry_main(arguments)
  command = arguments.shift
  options = {}
  parser = OptionParser.new do |flags|
    flags.on("--registry-dir PATH") { |value| options[:directory] = value }
    flags.on("--name NAME") { |value| options[:name] = value }
    flags.on("--checkout PATH") { |value| options[:checkout] = value }
    flags.on("--udid UDID") { |value| options[:udid] = value }
    flags.on("--device NAME") { |value| options[:device] = value }
    flags.on("--os VERSION") { |value| options[:os] = value }
    flags.on("--runtime-key KEY") { |value| options[:runtime_key] = value }
  end
  parser.parse!(arguments)
  abort("usage: simulator_registry.rb <resolve|delete-target|prune-target|record|forget> [options]") unless command
  registry = SimulatorRegistry.new(directory: options.fetch(:directory))

  case command
  when "resolve"
    inventory = JSON.parse($stdin.read)
    result = registry.resolve(
      name: options.fetch(:name),
      checkout: options.fetch(:checkout),
      device: options.fetch(:device),
      os: options.fetch(:os),
      runtime_key: options.fetch(:runtime_key),
      all: inventory.fetch("all"),
      available: inventory.fetch("available"),
    )
    puts [result.action, result.udid].compact.join("\t")
  when "delete-target"
    result = registry.deletion_target(
      name: options.fetch(:name),
      checkout: options.fetch(:checkout),
      device: options.fetch(:device),
      os: options.fetch(:os),
      runtime_key: options.fetch(:runtime_key),
      all: JSON.parse($stdin.read),
    )
    puts [result.action, result.udid].compact.join("\t")
  when "prune-target"
    result = registry.prune_target(
      name: options.fetch(:name),
      runtime_key: options.fetch(:runtime_key),
      all: JSON.parse($stdin.read),
    )
    puts [result.action, result.udid].compact.join("\t")
  when "record"
    registry.record(
      name: options.fetch(:name),
      checkout: options.fetch(:checkout),
      udid: options.fetch(:udid),
      device: options.fetch(:device),
      os: options.fetch(:os),
    )
  when "forget"
    registry.forget(options.fetch(:name))
  else
    abort("unknown simulator registry command: #{command}")
  end
  0
rescue KeyError, JSON::ParserError, RuntimeError => error
  warn "error: #{error.message}"
  1
end

exit(simulator_registry_main(ARGV)) if __FILE__ == $PROGRAM_NAME
