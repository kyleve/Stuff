# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "tmpdir"
require "uri"
require "zlib"
require_relative "../../../Tools/file_transaction"

# Refresh and replay only create a candidate. Installation is a separate, offline operation.
class RegionRelease
  INPUTS = %w[north-america.geojson.gz report.json sources.lock.json].freeze
  OUTPUTS = %w[regions regions.json].freeze
  COUNTRIES = %w[canada united-states].freeze
  CANADA_CODES = %w[10 11 12 13 24 35 46 47 48 59 60 61 62]
    .zip(%w[NL PE NS NB QC ON MB SK AB BC YT NT NU]).to_h.freeze
  PROVINCES = CANADA_CODES.values.sort.freeze
  US_COUNTRY_ONLY = %w[AS GU MP VI].freeze
  YEARS = /\A20[0-9]{2}\z/
  SHA256 = /\A[a-f0-9]{64}\z/

  class InstallTransaction < FileTransaction
    def initialize(directory)
      super()
      @backup_directory = directory
    end

    private

    def backup_path(target)
      File.join(@backup_directory, "old-#{File.basename(target)}")
    end
  end

  def initialize(root: File.expand_path("..", __dir__), transaction: InstallTransaction)
    @root = root
    @source = File.join(root, "Tools/source")
    @resources = File.join(root, "Sources/Resources")
    @release = File.join(@source, "release")
    @journal = File.join(root, ".region-adoption")
    @transaction = transaction
  end

  def run(arguments)
    options = {}
    modes = []
    parser = OptionParser.new do |p|
      p.banner = "Usage: generate-regions.rb [--refresh | --replay LOCK | --adopt DIR | --check]"
      p.on("--refresh", "Fetch a dated release; requires both years, cache and output") { modes << :refresh }
      p.on("--replay LOCK", "Rebuild from verified cached inputs") { |v| modes << :replay; options[:lock] = v }
      p.on("--adopt DIR", "Validate and install a candidate") { |v| modes << :adopt; options[:candidate] = v }
      p.on("--check", "Compare the bundle with an offline regeneration") { modes << :check }
      p.on("--us-year YEAR", YEARS, "TIGER/Line release year") { |v| options[:us_year] = v }
      p.on("--ca-year YEAR", YEARS, "Statistics Canada census year") { |v| options[:ca_year] = v }
      p.on("--cache DIR", "Content-addressed raw downloads") { |v| options[:cache] = v }
      p.on("--output DIR", "New directory for a candidate") { |v| options[:output] = v }
    end
    parser.parse!(arguments)
    raise ArgumentError, parser.to_s unless arguments.empty? && modes.length <= 1
    mode = modes.first || :generate
    keys = { refresh: %i[us_year ca_year cache output], replay: %i[lock cache output],
             adopt: [:candidate], check: [], generate: [] }.fetch(mode)
    raise ArgumentError, parser.to_s unless options.keys.sort == keys.sort

    if %i[refresh replay].include?(mode)
      build_candidate(mode, options)
      return
    end

    # The entry point is a stable existing inode in a checkout. Opening it read-only
    # also permits --check in read-only checkouts and leaves no lock file behind.
    File.open(File.join(@root, "Tools/generate-regions.rb"), "r") do |file|
      file.flock(File::LOCK_EX)
      if mode == :check
        raise "Interrupted adoption. Rerun --adopt to recover." if File.exist?(@journal)
        check
      else
        recover if File.directory?(@journal)
        mode == :adopt ? adopt(File.expand_path(options.fetch(:candidate))) : regenerate
      end
    end
  end

  private

  def build_candidate(mode, options)
    output = absolute_path(options.fetch(:output))
    cache = absolute_path(options.fetch(:cache))
    root = File.realpath(@root)
    if inside?(output, root) || inside?(cache, root) || inside?(output, cache) || inside?(cache, output)
      raise "Choose separate cache and candidate directories outside RegionKit"
    end
    raise "Output directory already exists: #{output}" if File.exist?(output) || File.symlink?(output)
    FileUtils.mkdir_p(File.dirname(output))
    Dir.mktmpdir(".regions-candidate-", File.dirname(output)) do |workspace|
      stage = File.join(workspace, "candidate")
      Dir.mkdir(stage)
      args = mode == :replay ? ["--replay", File.expand_path(options.fetch(:lock))] :
        ["--refresh", "--us-year", options.fetch(:us_year), "--ca-year", options.fetch(:ca_year)]
      converter = File.join(@root, "Tools/convert_boundaries.py")
      python = ENV.fetch("REGIONKIT_PYTHON", "python3")
      raise "Boundary conversion failed" unless system(python, "-B", converter, *args, "--cache", cache, "--output", stage)
      lock = validate_inputs(stage)
      previous = File.join(@release, "sources.lock.json")
      if mode == :refresh && File.file?(previous)
        known = JSON.parse(File.read(previous)).fetch("inputs").to_h { |i| [i.fetch("url"), i.fetch("sha256")] }
        lock.fetch("inputs").each do |i|
          old = known[i.fetch("url")]
          warn "Changed publisher bytes for #{i.fetch("url")}: #{old} -> #{i.fetch("sha256")}" if old && old != i.fetch("sha256")
        end
      end
      resources = File.join(stage, "resources")
      generate(resources, stage)
      validate_catalog(resources)
      File.write(File.join(stage, "bundle-report.json"), JSON.pretty_generate(bundle_inventory(resources)) + "\n")
      report_changes(resources)
      # Place a completed tree in the requested (new) destination, in one rename.
      raise "Output already exists: #{output}" if File.exist?(output)
      File.rename(stage, output)
    end
    puts "Candidate ready: #{output}"
  end

  # Resolve existing path components, including symlinks above a new directory.
  def absolute_path(path)
    expanded = File.expand_path(path)
    return File.realpath(expanded) if File.exist?(expanded)
    raise "Dangling symlink: #{expanded}" if File.symlink?(expanded)
    File.join(absolute_path(File.dirname(expanded)), File.basename(expanded))
  end

  def inside?(path, parent)
    path == parent || path.start_with?(parent + File::SEPARATOR)
  end

  def validate_inputs(dir)
    lock = JSON.parse(File.binread(regular_file(dir, "sources.lock.json")))
    raise "Unsupported release lock version" unless lock.fetch("version") == 1
    validate_provenance(lock)
    validate_pins(lock)
    { "normalized" => INPUTS[0], "report" => INPUTS[1] }.each do |key, name|
      record = lock.fetch(key)
      raise "Unexpected #{key} filename" unless record.fetch("file") == name
      actual = Digest::SHA256.file(regular_file(dir, name)).hexdigest
      raise "Hash mismatch for #{name}" unless record.fetch("sha256") == actual
    end
    report = JSON.parse(File.binread(regular_file(dir, "report.json")))
    validate_membership(report.fetch("sourceMembership"), lock.fetch("caYear"))
    lock
  end

  def validate_provenance(lock)
    { "census" => "usYear", "statcan" => "caYear" }.each do |publisher, year_key|
      year = lock.fetch(year_key)
      raise "Invalid #{year_key}" unless year.is_a?(Integer) && YEARS.match?(year.to_s)
      source = lock.fetch("sources").fetch(publisher)
      require_text(source, %w[product publisher includes license], publisher)
      raise "Wrong #{publisher} reference date" unless source.fetch("referenceDate") == "#{year}-01-01"
    end
    chain = lock.fetch("toolchain")
    require_text(chain, %w[python GEOS PROJ], "toolchain")
    require_text(chain.fetch("packages"), %w[numpy pyproj pyshp shapely certifi], "package")
    unless SHA256.match?(chain.fetch("projectionDatabaseSHA256")) && chain.fetch("projectionNetworkEnabled") == false
      raise "Incomplete offline projection pins"
    end
    conversion = lock.fetch("conversion")
    require_text(conversion, %w[algorithm winding], "conversion")
    unless conversion.fetch("normalizedEPSG") == 4326 && conversion.fetch("coordinateDecimals").is_a?(Integer) &&
           conversion.fetch("toleranceMetres").is_a?(Numeric) && conversion.fetch("toleranceMetres") >= 0 &&
           conversion.fetch("canadianRequest").fetch("outSR") == 4326
      raise "Incomplete WGS84 conversion settings"
    end
  end

  def require_text(record, keys, purpose)
    keys.each do |key|
      value = record.fetch(key)
      raise "Missing #{purpose} #{key}" unless value.is_a?(String) && !value.strip.empty?
    end
  end

  def validate_pins(lock)
    pins = lock.fetch("inputs")
    features = CANADA_CODES.keys.map { |id| "statcan-#{id}" }
    expected = %w[census-state statcan-service statcan-layer statcan-inventory] + features
    # For 2026 the adapter carries independently verified topology counts. For
    # other vintages its native PBF responses must be pinned for offline replay.
    expected += features.map { |feature| "#{feature}-topology" } unless lock.fetch("caYear") == 2026
    raise "Missing or duplicate release input pins" unless pins.map { |pin| pin.fetch("key") }.sort == expected.sort
    service = "/geo_wa/rest/services/#{lock.fetch("caYear")}/Cartographic_boundary_files/MapServer"
    layer = URI.parse(pins.find { |pin| pin.fetch("key") == "statcan-layer" }.fetch("url")).path
    pins.each do |pin|
      key, bytes, checksum = pin.values_at("key", "bytes", "sha256")
      raise "Invalid checksum or size for #{key}" unless bytes.is_a?(Integer) && bytes.positive? && SHA256.match?(checksum)
      url = URI.parse(pin.fetch("url"))
      raise "Expected an HTTPS publisher URL for #{key}" unless url.is_a?(URI::HTTPS) && !url.userinfo && !url.fragment
      if key == "census-state"
        year = lock.fetch("usYear")
        valid = url.host == "www2.census.gov" && url.path == "/geo/tiger/TIGER#{year}/STATE/tl_#{year}_us_state.zip"
      else
        params = URI.decode_www_form(url.query.to_s).to_h
        valid = url.host == "geo.statcan.gc.ca" && case key
        when "statcan-service" then url.path == service && params["f"] == "pjson"
        when "statcan-layer" then url.path.match?(%r{\A#{service}/\d+\z}) && params["f"] == "pjson"
        else
          uid = key.delete_prefix("statcan-").delete_suffix("-topology")
          query = if key == "statcan-inventory"
                    { "where" => "1=1", "f" => "geojson", "returnGeometry" => "false" }
                  elsif key.end_with?("-topology")
                    { "where" => "PRUID='#{uid}'", "f" => "pbf", "outFields" => "PRUID", "outSR" => "3347", "returnGeometry" => "true" }
                  else
                    { "where" => "PRUID='#{uid}'", "f" => "geojson", "outSR" => "4326", "returnGeometry" => "true" }
                  end
          url.path == "#{layer}/query" && params.slice(*query.keys) == query
        end
      end
      raise "Wrong publisher URL for #{key}" unless valid
    end
  end

  def validate_membership(members, ca_year)
    us, canada = members.partition { |row| row.fetch("countryID") == "united-states" }
    us_codes = us.map { |row| row.fetch("STUSPS") }
    unless us_codes.sort == (US_TRACKING_CODES + US_COUNTRY_ONLY).sort && us.map { |row| row.fetch("STATEFP") }.uniq.size == us.size
      raise "Invalid US country membership"
    end
    us.each do |row|
      code = row.fetch("STUSPS")
      fips = row.fetch("STATEFP")
      expected = US_COUNTRY_ONLY.include?(code) ? nil : "us-#{code}"
      unless /\A\d{2}\z/.match?(fips) && row.fetch("GEOID") == fips && row.fetch("catalogID") == expected
        raise "Invalid US source member #{code}"
      end
    end
    raise "Invalid Canadian country membership" unless canada.map { |row| row.fetch("PRUID") }.sort == CANADA_CODES.keys.sort
    canada.each do |row|
      uid = row.fetch("PRUID")
      code = CANADA_CODES.fetch(uid)
      unless row.fetch("countryID") == "canada" && row.fetch("postalCode") == code &&
             row.fetch("DGUID") == "#{ca_year}A0002#{uid}" && row.fetch("catalogID") == "ca-#{code}"
        raise "Invalid Canadian source member #{uid}"
      end
    end
  end

  def regular_file(dir, name)
    path = File.join(dir, name)
    raise "Missing or invalid release file: #{path}" unless File.file?(path) && !File.symlink?(path)
    path
  end

  def generate(resources, release)
    RegionGenerator.new(source: @source, resources: resources).run(release: release)
  end

  def regenerate
    install_resources do |staged|
      validate_inputs(@release)
      generate(staged, @release)
      validate_catalog(staged)
    end
  end

  def check
    Dir.mktmpdir("region-check") do |staged|
      validate_inputs(@release)
      generate(staged, @release)
      validate_catalog(staged)
      compare_resources(staged, @resources)
    end
    puts "Bundled region resources match the normalized sources."
  end

  def validate_catalog(resources)
    records = JSON.parse(File.binread(regular_file(resources, "regions.json")))
    by_id = records.to_h { |record| [record.fetch("id"), record] }
    states = US_TRACKING_CODES.map { |code| "us-#{code}" }
    provinces = PROVINCES.map { |code| "ca-#{code}" }
    expected = states + provinces + COUNTRIES + ["european-union"]
    raise "Incomplete catalog" unless records.length == expected.length && by_id.keys.sort == expected.sort
    expected.each do |id|
      node = by_id.fetch(id)
      parent = states.include?(id) ? "united-states" : (provinces.include?(id) ? "canada" : nil)
      raise "Wrong parent for #{id}" unless node["parentID"] == parent
      kind = if COUNTRIES.include?(id)
               "country"
             elsif id == "european-union"
               "bloc"
             elsif id == "us-DC"
               "federalDistrict"
             elsif %w[us-PR ca-NT ca-NU ca-YT].include?(id)
               "territory"
             else
               states.include?(id) ? "state" : "province"
             end
      source = if id == "european-union"
                 "original"
               elsif parent == "united-states" || id == "united-states"
                 "census"
               else
                 "statcan"
               end
      raise "Wrong source for #{id}" unless node.fetch("source") == source
      raise "Wrong kind for #{id}" unless node.fetch("kind") == kind
      raise "Wrong eligibility for #{id}" unless node.fetch("isLoggable") == (id != "united-states")
      file = id + (source == "original" ? ".geojson" : ".twkb")
      raise "Unexpected geometry for #{id}" unless node.fetch("geometry").fetch("file") == file
      regular_file(File.join(resources, "regions"), file)
    end
  end

  def bundle_inventory(resources)
    rows = JSON.parse(File.read(File.join(resources, "regions.json")))
    sizes = rows.to_h do |node|
      file = File.join(resources, "regions", node.fetch("geometry").fetch("file"))
      [node.fetch("id"), File.size(file)]
    end
    available = rows.select { |node| node.fetch("isLoggable") }.map { |node| node.fetch("id") }
    defaults = %w[us-CA us-NY canada european-union]
    { "allBytes" => sizes.values.sum, "loggableBytes" => sizes.values_at(*available).sum,
      "defaultBytes" => sizes.values_at(*defaults).sum, "largestID" => sizes.max_by(&:last).first,
      "bytesByID" => sizes }
  end

  def report_changes(resources)
    current = File.join(@resources, "regions.json")
    return unless File.file?(current)
    previous = JSON.parse(File.read(current)).to_h { |node| [node.fetch("id"), node["parentID"]] }
    incoming = JSON.parse(File.read(File.join(resources, "regions.json"))).to_h { |node| [node.fetch("id"), node["parentID"]] }
    puts "Added IDs: #{(incoming.keys - previous.keys).join(', ')}"
    puts "Removed IDs: #{(previous.keys - incoming.keys).join(', ')}"
    puts "Changed parents: #{(incoming.keys & previous.keys).select { |id| incoming[id] != previous[id] }.join(', ')}"
  end

  def compare_resources(expected, actual)
    OUTPUTS.each do |name|
      raise "Generated output differs: #{name}" unless digest(File.join(expected, name)) == digest(File.join(actual, name))
    end
  end

  def digest(path)
    raise "Missing or unexpected symlink: #{path}" unless File.exist?(path) && !File.symlink?(path)
    return Digest::SHA256.file(path).hexdigest if File.file?(path)
    sha = Digest::SHA256.new
    Dir.children(path).sort.each { |name| sha << name << "\0" << digest(File.join(path, name)) }
    sha.hexdigest
  end

  def adopt(candidate)
    install_resources(release: candidate) do |staged, release|
      generate(staged, release)
      validate_catalog(staged)
      compare_resources(staged, File.join(candidate, "resources"))
    end
    puts "Adopted region release from #{candidate}"
  end

  # The journal contains a complete verified new release, so recovery can finish
  # an interrupted install without the original candidate or an upstream service.
  def install_resources(release: nil)
    Dir.mktmpdir(".region-stage-", @root) do |workspace|
      stage = File.join(workspace, "install")
      Dir.mkdir(stage)
      resources = File.join(stage, "resources")
      staged_release = nil
      if release
        # Validate and generate from the exact bytes that will enter the journal.
        # The candidate is external to this checkout's writer lock.
        staged_release = File.join(stage, "release")
        FileUtils.mkdir(staged_release)
        INPUTS.each { |name| FileUtils.cp(regular_file(release, name), File.join(staged_release, name)) }
        validate_inputs(staged_release)
      end
      yield resources, staged_release
      inventory = targets(stage).to_h { |relative, _| [relative, digest(File.join(stage, relative))] }
      File.write(File.join(stage, "inventory.json"), JSON.generate(inventory))
      File.rename(stage, @journal)
    end
    recover
  end

  def targets(stage)
    dirs = OUTPUTS.to_h { |name| ["resources/#{name}", File.join(@resources, name)] }
    dirs["release"] = @release if File.directory?(File.join(stage, "release"))
    dirs
  end

  def recover
    inventory = JSON.parse(File.binread(regular_file(@journal, "inventory.json")))
    replacements = targets(@journal)
    raise "Invalid region install journal" unless replacements.keys.sort == inventory.keys.sort
    replacements.each_key do |relative|
      raise "Damaged staged #{relative}" unless digest(File.join(@journal, relative)) == inventory.fetch(relative)
    end
    # Each attempt owns its staging copies and transaction backups. An interrupted
    # attempt remains in the journal and is discarded once all targets verify.
    attempt = Dir.mktmpdir("apply-", @journal)
    txn = @transaction.new(attempt)
    replacements.each do |relative, target|
      next if File.exist?(target) && digest(target) == inventory.fetch(relative)
      copy = File.join(attempt, File.basename(target))
      FileUtils.cp_r(File.join(@journal, relative), copy)
      txn.replace(target: target, staged: copy)
    end
    begin
      txn.commit
    rescue FileTransaction::CleanupError => error
      warn error.message
    end
    replacements.each { |relative, target| raise "Incomplete install: #{target}" unless digest(target) == inventory.fetch(relative) }
    completed = Dir.mktmpdir(".region-installed-", @root)
    File.rename(@journal, completed)
    begin
      FileUtils.remove_entry(completed)
    rescue SystemCallError => error
      warn "Release installed. Remove completed installation #{completed}: #{error.message}"
    end
  end
end
