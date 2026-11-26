# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "tmpdir"
require "uri"
require "zlib"
require_relative "../../../Tools/file_transaction"
require_relative "generate-regions" unless defined?(RegionGenerator)

# Refresh and replay only create a candidate. Installation is a separate, offline operation.
class RegionRelease
  INPUTS = (RegionGenerator::NORMALIZED.values + %w[report.json sources.lock.json]).freeze
  OUTPUTS = %w[regions regions.json].freeze
  COUNTRIES = %w[canada united-states].freeze
  CANADA_CODES = %w[10 11 12 13 24 35 46 47 48 59 60 61 62]
    .zip(%w[NL PE NS NB QC ON MB SK AB BC YT NT NU]).to_h.freeze
  PROVINCES = CANADA_CODES.values.sort.freeze
  US_UNTRACKED_CODES = %w[AS GU MP VI].freeze
  STATCAN_SERVICES = { "statcanDigital" => "Digital_boundary_files", "statcanCartographic" => "Cartographic_boundary_files" }.freeze
  YEARS = /\A20[0-9]{2}\z/
  SHA256 = /\A[a-f0-9]{64}\z/
  TRACKING_CAP_METRES = 25

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
      p.on("--refresh", "Fetch a dated release; requires three source years, cache and output") { modes << :refresh }
      p.on("--replay LOCK", "Rebuild from verified cached inputs") { |v| modes << :replay; options[:lock] = v }
      p.on("--adopt DIR", "Validate and install a candidate") { |v| modes << :adopt; options[:candidate] = v }
      p.on("--check", "Compare the bundle with an offline regeneration") { modes << :check }
      p.on("--us-year YEAR", YEARS, "TIGER/Line release year") { |v| options[:us_year] = v }
      p.on("--us-display-year YEAR", YEARS, "Census 1:500,000 cartographic release year") { |v| options[:us_display_year] = v }
      p.on("--ca-year YEAR", YEARS, "Statistics Canada census year") { |v| options[:ca_year] = v }
      p.on("--cache DIR", "Content-addressed raw downloads") { |v| options[:cache] = v }
      p.on("--output DIR", "New directory for a candidate") { |v| options[:output] = v }
    end
    parser.parse!(arguments)
    raise ArgumentError, parser.to_s unless arguments.empty? && modes.length <= 1
    mode = modes.first || :generate
    keys = { refresh: %i[us_year us_display_year ca_year cache output], replay: %i[lock cache output],
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
        ["--refresh", "--us-year", options.fetch(:us_year), "--us-display-year", options.fetch(:us_display_year), "--ca-year", options.fetch(:ca_year)]
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
      validate_catalog(resources, stage)
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

  def release_lock(dir)
    lock = JSON.parse(File.binread(regular_file(dir, "sources.lock.json")))
    unless lock.fetch("version") == 4
      raise "Unsupported release lock version. Run --refresh with --us-year, --us-display-year and --ca-year to certify every tracking boundary."
    end
    lock
  end

  def validate_inputs(dir)
    lock = release_lock(dir)
    validate_provenance(lock)
    validate_pins(lock)
    normalized = lock.fetch("normalized")
    raise "Missing normalized products" unless normalized.keys.sort == RegionGenerator::NORMALIZED.keys.sort
    RegionGenerator::NORMALIZED.each { |purpose, name| verify_hash(dir, name, normalized.fetch(purpose)) }
    verify_hash(dir, "report.json", lock.fetch("report"))
    report = JSON.parse(File.binread(regular_file(dir, "report.json")))
    membership = report.fetch("sourceMembership")
    RegionGenerator::NORMALIZED.each_key { |purpose| validate_membership(membership.fetch(purpose), lock.fetch("caYear")) }
    # Postal and catalog IDs agree even when the two products advance independently.
    identities = membership.values_at("tracking", "display").map do |rows|
      rows.map { |row| row.slice("STUSPS", "STATEFP", "GEOID", "PRUID", "DGUID", "catalogID") }
          .sort_by { |row| [row["STUSPS"].to_s, row["PRUID"].to_s] }
    end
    raise "Tracking and display source members disagree" unless identities.first == identities.last
    validate_accuracy(report.fetch("trackingAccuracy"), lock, membership.fetch("tracking"))
    lock
  end

  def verify_hash(dir, name, pin)
    raise "Unexpected filename for #{name}" unless pin.fetch("file") == name
    raise "Hash mismatch for #{name}" unless pin.fetch("sha256") == Digest::SHA256.file(regular_file(dir, name)).hexdigest
  end

  def validate_accuracy(accuracy, lock, inventory)
    raise "Incorrect tracking displacement cap" unless accuracy.fetch("capMetres") == TRACKING_CAP_METRES
    members = accuracy.fetch("members")
    tracked = inventory.select { |row| row.fetch("catalogID") }
    raise "Tracking certificate membership differs from the source inventory" unless members.keys.sort == tracked.map { |row| row.fetch("catalogID") }.sort
    pins = lock.fetch("inputs").to_h { |pin| [pin.fetch("key"), pin.fetch("sha256")] }
    bounds = tracked.map do |row|
      id = row.fetch("catalogID")
      member = members.fetch(id)
      expected_pins = tracking_source_keys(row).to_h { |key| [key, pins.fetch(key)] }
      raise "Incorrect source hashes for #{id}" unless member.fetch("sourceSHA256") == expected_pins
      bound = member.fetch("upperBoundMetres")
      unless bound.is_a?(Numeric) && bound.between?(0, TRACKING_CAP_METRES) && SHA256.match?(member.fetch("sha256"))
        raise "Invalid tracking accuracy certificate for #{id}"
      end
      bound
    end
    raise "Incorrect maximum tracking bound" unless bounds.max == accuracy.fetch("maximumUpperBoundMetres")
  end

  def tracking_source_keys(row)
    product = RegionGenerator::PRODUCTS.fetch(row.fetch("countryID")).fetch("tracking")
    case product
    when "censusTIGER" then ["censusTIGER-state"]
    when "statcanDigital"
      key = "statcanDigital-#{row.fetch("PRUID")}"
      [key, "#{key}-topology"]
    else raise "Missing tracking source pin mapping for #{product}"
    end
  end

  def validate_provenance(lock)
    sources = lock.fetch("sources")
    raise "Expected all four source products" unless sources.keys.sort == RegionGenerator::YEARS.keys.sort
    RegionGenerator::YEARS.each do |product, year_key|
      year = lock.fetch(year_key)
      raise "Invalid #{year_key}" unless year.is_a?(Integer) && YEARS.match?(year.to_s)
      source = sources.fetch(product)
      require_text(source, %w[product publisher includes license], product)
      raise "Wrong #{product} reference date" unless source.fetch("referenceDate") == "#{year}-01-01"
    end
    chain = lock.fetch("toolchain")
    require_text(chain, %w[python GEOS PROJ], "toolchain")
    require_text(chain.fetch("packages"), %w[numpy pyproj pyshp shapely certifi], "package")
    unless SHA256.match?(chain.fetch("projectionDatabaseSHA256")) && chain.fetch("projectionNetworkEnabled") == false
      raise "Incomplete offline projection pins"
    end
    conversion = lock.fetch("conversion")
    require_text(conversion, %w[algorithm winding], "conversion")
    tracking = conversion.fetch("tracking")
    require_text(tracking, ["restorationMethod"], "tracking")
    unless conversion.fetch("normalizedEPSG") == 4326 && conversion.fetch("coordinateDecimals") == 7 &&
           conversion.fetch("canadianRequest") == { "outSR" => 4326, "displayGeometryPrecision" => 7, "serverReprojects" => true } &&
           conversion.fetch("usSourceEPSG") == 4269 && conversion.fetch("canadianProjection") == 3347 &&
           %w[continental AK HI PR].all? { |group| conversion.fetch("usProjections").fetch(group).is_a?(Integer) } &&
           conversion.fetch("canadianNearDuplicateToleranceMetres") == 0.02 &&
           tracking.fetch("maximumDisplacementMetres") == TRACKING_CAP_METRES && tracking.fetch("initialToleranceMetres") == 180
      raise "Incorrect WGS84 or tracking simplification settings"
    end
    %w[usDisplay caDisplay].each do |role|
      tolerance = conversion.fetch(role).fetch("toleranceMetres")
      raise "Invalid tolerance for #{role}" unless tolerance.is_a?(Numeric) && tolerance >= 0
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
    expected = {
      "censusTIGER-state" => "https://www2.census.gov/geo/tiger/TIGER#{lock.fetch("usYear")}/STATE/tl_#{lock.fetch("usYear")}_us_state.zip",
      "censusCartographic-state" => "https://www2.census.gov/geo/tiger/GENZ#{lock.fetch("usDisplayYear")}/shp/cb_#{lock.fetch("usDisplayYear")}_us_state_500k.zip",
    }
    ca_year = lock.fetch("caYear")
    STATCAN_SERVICES.each do |product, service|
      url = "https://geo.statcan.gc.ca/geo_wa/rest/services/#{ca_year}/#{service}/MapServer"
      expected["#{product}-service"] = [url, { "f" => "pjson" }]
      expected["#{product}-layer"] = [%r{\A#{Regexp.escape(url)}/\d+\z}, { "f" => "pjson" }]
      layer_pin = pins.find { |pin| pin.fetch("key") == "#{product}-layer" }
      raise "Missing or duplicate release input pins" unless layer_pin
      layer = layer_pin.fetch("url").split("?").first
      query = "#{layer}/query"
      fields = "PRUID,DGUID,PRENAME,PRFNAME"
      expected["#{product}-inventory"] = [query, {
        "where" => "1=1", "f" => "geojson", "returnGeometry" => "false", "outFields" => fields, "orderByFields" => "PRUID",
      }]
      CANADA_CODES.each_key do |id|
        feature = { "where" => "PRUID='#{id}'", "returnGeometry" => "true" }
        geometry = feature.merge("outSR" => "4326", "f" => "geojson", "outFields" => fields)
        geometry["geometryPrecision"] = "7" if product == "statcanCartographic"
        expected["#{product}-#{id}"] = [query, geometry]
        if product == "statcanDigital" || ca_year != 2026
          expected["#{product}-#{id}-topology"] = [query, feature.merge("outSR" => "3347", "f" => "pbf", "outFields" => "PRUID")]
        end
      end
    end
    raise "Missing or duplicate release input pins" unless pins.map { |pin| pin.fetch("key") }.sort == expected.keys.sort
    pins.each do |pin|
      key, bytes, checksum = pin.values_at("key", "bytes", "sha256")
      raise "Invalid checksum or size for #{key}" unless bytes.is_a?(Integer) && bytes.positive? && SHA256.match?(checksum)
      uri = URI.parse(pin.fetch("url"))
      raise "Expected an HTTPS publisher URL for #{key}" unless uri.is_a?(URI::HTTPS) && !uri.userinfo && !uri.fragment
      location, params = expected.fetch(key)
      actual = uri.dup
      actual.query = nil
      valid = location === actual.to_s
      # Extra or duplicate ArcGIS parameters can change the returned geometry.
      valid &&= params ? (URI.decode_www_form(uri.query.to_s).sort == params.to_a.sort) : uri.query.nil?
      raise "Wrong publisher URL for #{key}" unless valid
    end
  end

  def validate_membership(members, ca_year)
    us, canada = members.partition { |row| row.fetch("countryID") == "united-states" }
    us_codes = us.map { |row| row.fetch("STUSPS") }
    unless us_codes.sort == (US_TRACKING_CODES + US_UNTRACKED_CODES).sort && us.map { |row| row.fetch("STATEFP") }.uniq.size == us.size
      raise "Invalid US source inventory"
    end
    us.each do |row|
      code = row.fetch("STUSPS")
      fips = row.fetch("STATEFP")
      expected = US_UNTRACKED_CODES.include?(code) ? nil : "us-#{code}"
      unless /\A\d{2}\z/.match?(fips) && row.fetch("GEOID") == fips && row.fetch("catalogID") == expected
        raise "Invalid US source member #{code}"
      end
    end
    raise "Invalid Canadian source inventory" unless canada.map { |row| row.fetch("PRUID") }.sort == CANADA_CODES.keys.sort
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
      validate_catalog(staged, @release)
    end
  end

  def check
    Dir.mktmpdir("region-check") do |staged|
      validate_inputs(@release)
      generate(staged, @release)
      validate_catalog(staged, @release)
      compare_resources(staged, @resources)
    end
    puts "Bundled region resources match the normalized sources."
  end

  def validate_catalog(resources, release)
    lock = release_lock(release)
    certificates = JSON.parse(File.read(File.join(release, "report.json"))).fetch("trackingAccuracy").fetch("members")
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
      raise "Wrong kind for #{id}" unless node.fetch("kind") == kind
      raise "Wrong eligibility for #{id}" unless node.fetch("isLoggable") == (kind != "country")
      if kind == "country"
        raise "Unexpected geometry for #{id}" if node.key?("geometry")
        next
      end
      geometry = node.fetch("geometry")
      raise "Incomplete geometry for #{id}" unless geometry.keys.sort == RegionGenerator::NORMALIZED.keys.sort
      geometry.each do |purpose, descriptor|
        product = parent ? RegionGenerator::PRODUCTS.fetch(parent).fetch(purpose) : "original"
        file = RegionGenerator.geometry_file(id, parent, purpose)
        expected_descriptor = { "file" => file, "product" => product }
        expected_descriptor["year"] = lock.fetch(RegionGenerator::YEARS.fetch(product)) unless product == "original"
        raise "Unexpected #{purpose} geometry for #{id}" unless descriptor == expected_descriptor
        path = regular_file(File.join(resources, "regions"), file)
        next unless purpose == "tracking"
        # The existing hand-drawn EU file is the only tracking resource outside the release pipeline.
        next if id == "european-union" && product == "original"
        unless Digest::SHA256.file(path).hexdigest == certificates.fetch(id).fetch("sha256")
          raise "Tracking geometry for #{id} differs from the certified TWKB"
        end
      end
    end
    expected_files = records.flat_map { |node| node.fetch("geometry", {}).values.map { |descriptor| descriptor.fetch("file") } }.uniq
    expected_paths = expected_files + expected_files.map { |file| File.dirname(file) }.uniq
    paths = Dir.glob("**/*", File::FNM_DOTMATCH, base: File.join(resources, "regions")) - ["."]
    raise "Unexpected geometry files in resources" unless paths.sort == expected_paths.sort
  end

  def bundle_inventory(resources)
    rows = JSON.parse(File.read(File.join(resources, "regions.json")))
    paths = rows.select { |node| node.fetch("isLoggable") }.to_h do |node|
      [node.fetch("id"), node.fetch("geometry").transform_values { |descriptor| descriptor.fetch("file") }]
    end
    sizes = paths.values.flat_map(&:values).uniq.to_h { |file| [file, File.size(File.join(resources, "regions", file))] }
    bytes_by_id = paths.transform_values { |roles| roles.transform_values { |file| sizes.fetch(file) } }
    bytes_by_role = RegionGenerator::NORMALIZED.keys.to_h do |purpose|
      [purpose, bytes_by_id.values.sum { |roles| roles.fetch(purpose) }]
    end
    defaults = %w[us-CA us-NY european-union]
    { "uniqueBytes" => sizes.values.sum, "uniqueFiles" => sizes.size, "logicalReferences" => paths.values.sum(&:size),
      "bytesByRole" => bytes_by_role, "defaultTrackingBytes" => defaults.sum { |id| bytes_by_id.fetch(id).fetch("tracking") },
      "bytesByID" => bytes_by_id }
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

  def compare_resources(expected, actual, hint: nil)
    OUTPUTS.each do |name|
      next if digest(File.join(expected, name)) == digest(File.join(actual, name))
      raise ["Generated output differs: #{name}", hint].compact.join(". ")
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
      validate_catalog(staged, release)
      compare_resources(staged, File.join(candidate, "resources"),
                        hint: "Use --replay with the candidate lock and cache to recreate its resources before adoption")
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
        release_lock(release) # Give older candidates the format upgrade instructions before copying.
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
