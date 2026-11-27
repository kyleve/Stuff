#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "pathname"
require "set"
require "tmpdir"

# Orchestrate the repository upgrader and independently verify its output. Manifest
# transformations belong exclusively in Where/Tools/upgrade-backup.rb.
class UpgradeAndVerify
  PRESERVED_COLLECTIONS = %w[
    samples evidence manualDays dismissedIssues trackedRegions
    recordingDeviceProfiles recordingDeviceMetadataChanges recordingDeviceRemovals assets
    plannedStayRecords homeRegionRecords sampleAttributionRevisions
  ].freeze

  def initialize(argv)
    @options = { force: false }
    parser = OptionParser.new do |options|
      options.banner = "Usage: ruby upgrade_and_verify.rb INPUT [OUTPUT] [options]"
      options.on("--source-profile FILE", "Original installation profile or selection JSON") do |path|
        @source_profile_path = File.expand_path(path)
      end
      options.on("--device-models FILE", "Hardware identifiers keyed by installation UUID") do |path|
        @device_models_path = File.expand_path(path)
      end
      options.on("--force", "Replace an existing output archive") { @options[:force] = true }
      options.on("-h", "--help", "Show this help") do
        puts options
        exit
      end
    end
    arguments = parser.parse(argv)
    raise OptionParser::MissingArgument, "INPUT" if arguments.empty?
    raise OptionParser::InvalidArgument, "too many paths" if arguments.length > 2

    @input = File.expand_path(arguments.fetch(0))
    @output = File.expand_path(arguments[1] || default_output(@input))
    @repo_root = Pathname.new(__dir__).join("../../../..").expand_path.to_s
    @upgrader = File.join(@repo_root, "Where/Tools/upgrade-backup.rb")
  end

  def run
    validate_paths!
    source_manifest = read_manifest(@input)
    source_version = integer_format_version(source_manifest, "source")
    expected_counts = expected_counts(source_manifest)

    Dir.mktmpdir("where-backup-upgrade") do |work_directory|
      input_zip = if File.directory?(@input)
        zip_path = File.join(work_directory, "input.zip")
        run_command!("zip", "-q", "-r", zip_path, ".", chdir: @input)
        zip_path
      else
        @input
      end

      mapping = @source_profile_path ? ["--source-profile", @source_profile_path] : []
      mapping += ["--device-models", @device_models_path] if @device_models_path
      run_command!(
        "mise", "exec", "--", "ruby", @upgrader, input_zip, @output, *mapping,
        chdir: @repo_root,
      )
    end

    run_command!("unzip", "-tq", @output)
    upgraded_manifest = read_manifest(@output)
    destination_version = integer_format_version(upgraded_manifest, "upgraded")
    current_version = upgrader_current_version
    fail_with("upgraded format is v#{destination_version}; expected v#{current_version}") unless destination_version == current_version
    if @source_profile_path
      profile = JSON.parse(File.read(@source_profile_path))
      if added_source_profile?(profile, source_manifest, upgraded_manifest)
        expected_counts["recordingDeviceProfiles"] += 1
      end
    end
    models = @device_models_path ? JSON.parse(File.read(@device_models_path)) : {}
    expected_counts["recordingDeviceMetadataChanges"] += verify_model_events!(source_manifest, upgraded_manifest, models)
    verify_counts!(upgraded_manifest, expected_counts)
    Dir.mktmpdir("where-backup-verification") do |work_directory|
      configuration_path = File.join(work_directory, "configuration.json")
      File.write(
        configuration_path,
        JSON.pretty_generate(verification_configuration(upgraded_manifest)) + "\n",
      )
      run_swift_verification!(configuration_path)
    end

    puts "Verified Where backup v#{source_version} -> v#{destination_version}"
    puts "Output: #{@output}"
    puts "Counts: #{expected_counts.map { |key, count| "#{key}=#{count}" }.join(", ")}"
  end

  private

  def default_output(input)
    "#{input.sub(/\.zip\z/i, "")}-upgraded.zip"
  end

  def validate_paths!
    fail_with("input not found: #{@input}") unless File.exist?(@input)
    fail_with("upgrade script not found: #{@upgrader}") unless File.file?(@upgrader)
    fail_with("input and output resolve to the same path") if @input == @output
    fail_with("output already exists: #{@output} (pass --force only with approval)") if File.exist?(@output) && !@options[:force]
    fail_with("output directory not found: #{File.dirname(@output)}") unless File.directory?(File.dirname(@output))
  end

  def read_manifest(path)
    contents = if File.directory?(path)
      manifest_path = File.join(path, "manifest.json")
      fail_with("manifest.json not found in backup directory: #{path}") unless File.file?(manifest_path)
      File.read(manifest_path)
    else
      stdout, stderr, status = Open3.capture3("unzip", "-p", path, "manifest.json")
      fail_with("could not read manifest.json from #{path}: #{stderr.strip}") unless status.success? && !stdout.empty?
      stdout
    end
    JSON.parse(contents)
  rescue JSON::ParserError => error
    fail_with("invalid manifest JSON in #{path}: #{error.message}")
  end

  def integer_format_version(manifest, label)
    version = manifest["formatVersion"]
    fail_with("#{label} manifest formatVersion must be an integer") unless version.is_a?(Integer)
    version
  end

  def expected_counts(manifest)
    counts = PRESERVED_COLLECTIONS.to_h do |key|
      value = manifest.fetch(key, [])
      fail_with("source manifest #{key} must be an array") unless value.is_a?(Array)
      [key, value.length]
    end
    primary_regions = manifest.fetch("primaryRegions", manifest.fetch("trackedRegions", []))
    fail_with("source manifest primaryRegions must be an array") unless primary_regions.is_a?(Array)
    counts.merge("primaryRegions" => primary_regions.length)
  end

  # One profile may be added when an explicitly supplied profile filled a missing origin.
  def added_source_profile?(profile, source, result)
    return false if profile.keys == ["id"]
    selected = profile.fetch("id").downcase
    return false if source.fetch("recordingDeviceProfiles", []).any? { |item| item.fetch("id").downcase == selected }
    used = { "samples" => "recordingDeviceID", "sampleAttributionRevisions" => "changedByDeviceID" }.any? do |table, field|
      result_rows = result.fetch(table)
      source.fetch(table, []).each_with_index.any? do |row, index|
        restored = result_rows[index]
        row[field].nil? && restored && restored["id"] == row["id"] && restored[field]&.downcase == selected
      end
    end
    return false unless used
    fail_with("upgraded archive does not contain the supplied source profile") unless result.fetch("recordingDeviceProfiles").include?(profile)
    true
  end

  def verify_model_events!(source, result, models)
    table = "recordingDeviceMetadataChanges"
    original = source.fetch(table, [])
    original_ids = original.map { |row| row.fetch("id").downcase }
    ids = original_ids.to_set
    retained, added = result.fetch(table).partition { |row| ids.include?(row.fetch("id").downcase) }
    fail_with("original metadata event identities changed") unless retained.map { |row| row.fetch("id").downcase }.sort == original_ids.sort

    # Starting at v9 every original record can be compared directly. Earlier versions
    # have documented transformations for dates, regions, device payloads and attribution.
    if source.fetch("formatVersion") >= 9
      obsolete = %w[recordingDevices recordingDeviceCheckIns recordingPolicyChanges]
      original_data = source.reject { |key, _| key == "formatVersion" || key == table || obsolete.include?(key) }
      restored_data = result.reject { |key, _| key == "formatVersion" || key == table }
      unless retained == original && original_data == restored_data
        fail_with("v9 or later manifest values changed during hardware model upgrade")
      end
    end

    field = "hardwareModelIdentifier"
    original_fact_targets = original.select { |row| row.dig("payload", "field") == field }.map { |row| row.fetch("deviceID").downcase }
    profiles = result.fetch("recordingDeviceProfiles").to_h { |row| [row.fetch("id").downcase, row] }
    needed = profiles.keys - original_fact_targets
    fail_with("unexpected added hardware model targets") unless added.map { |row| row.fetch("deviceID").downcase }.sort == needed.sort
    model_map = models.transform_keys(&:downcase)
    added.each do |event|
      target = event.fetch("deviceID").downcase
      model = model_map[target.delete_prefix("store://devices/")]
      unless model && event.fetch("payload") == { "field" => field, field => model } && event.fetch("revision") == 0 &&
             event.fetch("changedByDeviceID").downcase == target && event.fetch("changedAt") == profiles.fetch(target).fetch("registeredAt")
        fail_with("added metadata does not match the supplied model and immutable profile")
      end
    end
    added.length
  end

  def verify_counts!(manifest, expected_counts)
    expected_counts.each do |key, expected|
      value = manifest[key]
      fail_with("upgraded manifest is missing array #{key}") unless value.is_a?(Array)
      fail_with("#{key} count changed from #{expected} to #{value.length}") unless value.length == expected
    end
  end

  def upgrader_current_version
    match = File.read(@upgrader).match(/^CURRENT_FORMAT_VERSION = (\d+)$/)
    fail_with("could not determine current format version from #{@upgrader}") unless match
    match[1].to_i
  end

  def verification_configuration(manifest)
    {
      backupPath: @output,
      samplesCount: manifest.fetch("samples").length,
      evidenceCount: manifest.fetch("evidence").length,
      manualDaysCount: manifest.fetch("manualDays").length,
      dismissedIssuesCount: manifest.fetch("dismissedIssues").length,
      trackedRegionsCount: manifest.fetch("trackedRegions").length,
      primaryRegionsCount: manifest.fetch("primaryRegions").length,
      deviceProfilesCount: manifest.fetch("recordingDeviceProfiles").length,
      deviceChangesCount: manifest.fetch("recordingDeviceMetadataChanges").length,
      deviceRemovalsCount: manifest.fetch("recordingDeviceRemovals").length,
      plannedStayRecordsCount: manifest.fetch("plannedStayRecords").length,
      homeRegionRecordsCount: manifest.fetch("homeRegionRecords").length,
      sampleAttributionRevisionsCount: manifest.fetch("sampleAttributionRevisions").length,
      assetsCount: manifest.fetch("assets").length,
    }
  end

  def run_swift_verification!(configuration_path)
    run_command!(
      "./test", "--only",
      "WhereCoreTests/BackupServiceTests/upgradedBackupDecodesAndLoadsAssets()",
      chdir: @repo_root,
      environment: {
        "TEST_RUNNER_WHERE_BACKUP_VERIFICATION_CONFIG" => configuration_path,
      },
    )
  end

  def run_command!(*command, chdir: nil, environment: {})
    success = if chdir
      Dir.chdir(chdir) { system(environment, *command) }
    else
      system(environment, *command)
    end
    fail_with("command failed: #{command.join(" ")}") unless success
  end

  def fail_with(message)
    raise RuntimeError, message
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    UpgradeAndVerify.new(ARGV).run
  rescue OptionParser::ParseError, RuntimeError => error
    warn "error: #{error.message}"
    exit 1
  end
end
