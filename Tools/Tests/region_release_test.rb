# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require_relative "../../Where/RegionKit/Tools/generate-regions"
require_relative "../../Where/RegionKit/Tools/region_release"

class RegionReleaseTest < Minitest::Test
  def setup
    @work = Dir.mktmpdir
    @root = File.join(@work, "Where/RegionKit")
    @tools = File.join(@root, "Tools")
    @candidate = File.join(@work, "candidate")
    @source = File.join(@tools, "source")
    @resources = File.join(@root, "Sources/Resources")
    FileUtils.mkdir_p([@source, @candidate, @resources, File.join(@work, "Tools")])
    FileUtils.cp(File.expand_path("../file_transaction.rb", __dir__), File.join(@work, "Tools"))
    %w[generate-regions.rb region_release.rb tiny_wkb.rb].each do |file|
      FileUtils.cp(File.join(__dir__, "../../Where/RegionKit/Tools", file), @tools)
    end
    FileUtils.cp(File.join(SOURCE, "europeanUnion.geojson"), @source)
    File.write(File.join(@resources, "Localizable.xcstrings"), "unrelated")
    make_candidate
  end

  def teardown
    FileUtils.remove_entry(@work)
  end

  def test_check_detects_drift_and_regeneration_repairs_it_offline
    cli("--adopt", @candidate)
    cli("--check")
    us = File.join(@resources, "regions/us/us-CA.tracking.twkb")
    expected = File.binread(us)
    File.write(us, "changed")
    _out, error, status = invoke("--check")
    refute status.success?
    assert_includes error, "differs"
    assert_equal "changed", File.read(us)
    cli
    assert_equal expected, File.binread(us)
    cli("--check")
    assert_equal "unrelated", File.read(File.join(@resources, "Localizable.xcstrings"))
  end

  def test_adoption_replaces_flat_resources_with_geographic_groups_and_rejects_the_old_release
    directory = File.join(@resources, "regions")
    FileUtils.mkdir_p(directory)
    %w[canada.twkb united-states.twkb us-CA.twkb].each { |name| File.write(File.join(directory, name), "old resource") }
    cli("--adopt", @candidate)
    assert_equal %w[ca eu us], Dir.children(directory).sort
    assert_equal US_TRACKING_CODES.product(%w[tracking display]).map { |code, purpose| "us-#{code}.#{purpose}.twkb" }.sort, Dir.children(File.join(directory, "us")).sort
    assert_equal RegionRelease::PROVINCES.product(%w[tracking display]).map { |code, purpose| "ca-#{code}.#{purpose}.twkb" }.sort, Dir.children(File.join(directory, "ca")).sort
    assert_equal ["european-union.geojson"], Dir.children(File.join(directory, "eu"))
    cli("--check")

    stale = File.join(directory, "ca/canada.twkb")
    File.write(stale, "left behind by a previous generator")
    _out, error, status = invoke("--check")
    refute status.success?
    assert_includes error, "differs"
    assert_path_exists stale
    cli
    refute_path_exists stale

    lock_path = File.join(@candidate, "sources.lock.json")
    lock = JSON.parse(File.read(lock_path))
    [2, 3].each do |version|
      File.write(lock_path, JSON.generate(lock.merge("version" => version)))
      _out, error, status = invoke("--adopt", @candidate)
      refute status.success?
      assert_includes error, "--refresh with --us-year, --us-display-year and --ca-year"
    end
    cli("--check")
  end

  def test_rejects_a_country_feature_in_normalized_inputs
    path = File.join(@candidate, "north-america.geojson.gz")
    release = JSON.parse(Zlib::GzipReader.open(path, &:read))
    country = release.fetch("features").first
    country.fetch("properties").merge!("id" => "canada", "kind" => "country")
    Zlib::GzipWriter.open(path) { |gz| gz.write(JSON.generate(release)) }
    lock_path = File.join(@candidate, "sources.lock.json")
    lock = JSON.parse(File.read(lock_path))
    lock.fetch("normalized").fetch("tracking")["sha256"] = Digest::SHA256.file(path).hexdigest
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Expected a subdivision"
    refute_path_exists File.join(@resources, "regions.json")
  end

  def test_rejects_swapped_products_or_unmatched_display_members_before_installing
    cli("--adopt", @candidate)
    path = File.join(@candidate, RegionGenerator::NORMALIZED.fetch("display"))
    original = Zlib::GzipReader.open(path, &:read)
    lock_path = File.join(@candidate, "sources.lock.json")
    {
      "Expected a subdivision with the display product" => ->(features) { features.first.fetch("properties")["source"] = "censusTIGER" },
      "Duplicate display region" => ->(features) { features << features.first },
      "Missing display regions" => ->(features) { features.pop },
      "Unexpected display region" => ->(features) { features.first.fetch("properties")["id"] = "us-GU" },
    }.each do |message, mutate|
      release = JSON.parse(original)
      mutate.call(release.fetch("features"))
      Zlib::GzipWriter.open(path) { |gz| gz.write(JSON.generate(release)) }
      lock = JSON.parse(File.read(lock_path))
      pin_release_files(lock)
      File.write(lock_path, JSON.generate(lock))
      _out, error, status = invoke("--adopt", @candidate)
      refute status.success?
      assert_includes error, message
      refute_path_exists File.join(@root, ".region-adoption")
    end
    cli("--check")
  end

  def test_damaged_candidate_does_not_replace_previous_resources
    cli("--adopt", @candidate)
    file = File.join(@candidate, "resources/regions/ca/ca-ON.tracking.twkb")
    flat = File.join(@candidate, "resources/regions/ca-ON.twkb")
    File.rename(file, flat)
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "--replay"
    cli("--check")
    File.rename(flat, file)
    File.write(file, "wrong")
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "differs"
    refute File.exist?(File.join(@root, ".region-adoption"))
    cli("--check")

    File.write(File.join(@candidate, "report.json"), "{}")
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Hash mismatch"
    cli("--check")
  end

  def test_interrupted_adoption_can_finish_without_the_original_candidate
    interrupted = Class.new(RegionRelease::InstallTransaction) do
      def after_apply(index)
        Process.kill("KILL", Process.pid) if index.zero?
      end
    end
    child = fork do
      RegionRelease.new(root: @root, transaction: interrupted).run(["--adopt", @candidate])
    end
    _pid, status = Process.wait2(child)
    assert status.signaled?
    assert File.exist?(File.join(@root, ".region-adoption/inventory.json"))
    FileUtils.remove_entry(@candidate)
    cli
    cli("--check")
    refute File.exist?(File.join(@root, ".region-adoption"))
    assert_equal "unrelated", File.read(File.join(@resources, "Localizable.xcstrings"))
  end

  def test_external_edit_during_adoption_cannot_change_the_installed_inputs
    candidate_report = File.join(@candidate, "report.json")
    original = File.binread(candidate_report)
    editing_release = Class.new(RegionRelease) do
      define_method(:generate) do |resources, release|
        super(resources, release)
        File.write(candidate_report, "{}")
      end
    end
    capture_io { editing_release.new(root: @root).run(["--adopt", @candidate]) }
    assert_equal "{}", File.read(candidate_report)
    assert_equal original, File.binread(File.join(@source, "release", "report.json"))
    cli("--check")
  end

  def test_refresh_and_replay_stage_identical_candidates_and_preserve_the_installed_release_on_failure
    # Real adapters have their own GIS fixtures. This stand-in supplies their
    # output files so Ruby's public command, staging and adoption can run offline.
    converter = File.join(@work, "fixture-converter")
    File.write(converter, "#!#{RbConfig.ruby}\n" + <<~'RUBY')
      require "fileutils"
      args = ARGV.dup
      args.shift if args.first == "-B"
      abort "wrong converter" unless File.basename(args.shift) == "convert_boundaries.py"
      mode = args.shift
      stage = args.last
      source = ENV.fetch("REGION_FIXTURE_SOURCE")
      cache = ENV.fetch("REGION_FIXTURE_CACHE")
      lock = File.join(source, "sources.lock.json")
      expected = case mode
      when "--refresh" then ["--us-year", "2026", "--us-display-year", "2025", "--ca-year", "2026"]
      when "--replay"
        pin = args.first
        abort "fixture cache does not match replay lock" unless File.binread(pin) == File.binread(lock)
        [pin]
      else abort "unexpected mode"
      end
      abort "unexpected converter arguments: #{args.inspect}" unless args == expected + ["--cache", cache, "--output", stage]
      FileUtils.cp(File.join(source, "report.json"), stage)
      abort "fixture download failed" if mode == "--refresh" && ENV["REGION_FIXTURE_OFFLINE"]
      %w[north-america.geojson.gz north-america-display.geojson.gz sources.lock.json].each { |file| FileUtils.cp(File.join(source, file), stage) }
    RUBY
    FileUtils.chmod(0o755, converter)
    cache = File.join(File.realpath(@work), "cache")
    env = { "REGIONKIT_PYTHON" => converter, "REGION_FIXTURE_SOURCE" => @candidate, "REGION_FIXTURE_CACHE" => cache }
    refresh = ["--refresh", "--us-year", "2026", "--us-display-year", "2025", "--ca-year", "2026", "--cache", cache]
    fresh = File.join(@work, "fresh")
    _out, error, status = invoke(*refresh, "--output", fresh, env: env)
    assert status.success?, error
    inventory = JSON.parse(File.read(File.join(fresh, "bundle-report.json")))
    sizes = inventory.fetch("bytesByID")
    assert_equal sizes.values_at("us-CA", "us-NY", "european-union").sum { |roles| roles.fetch("tracking") }, inventory.fetch("defaultTrackingBytes")
    assert_equal sizes.values.sum { |roles| roles.fetch("display") }, inventory.fetch("bytesByRole").fetch("display")
    assert_equal 131, inventory.fetch("uniqueFiles")
    assert_equal 132, inventory.fetch("logicalReferences")
    assert_equal inventory.fetch("bytesByRole").values.sum - sizes.fetch("european-union").fetch("display"), inventory.fetch("uniqueBytes")
    cli("--adopt", fresh)
    installed_lock = File.binread(File.join(@source, "release", "sources.lock.json"))
    replay = File.join(@work, "replay")
    replay_args = ["--replay", File.join(fresh, "sources.lock.json"), "--cache", cache]
    _out, error, status = invoke(*replay_args, "--output", replay, env: env.merge("REGION_FIXTURE_OFFLINE" => "1"))
    assert status.success?, error
    files = Dir.glob("**/*", base: fresh).select { |name| File.file?(File.join(fresh, name)) }
    assert_equal files, Dir.glob("**/*", base: replay).select { |name| File.file?(File.join(replay, name)) }
    files.each { |name| assert_equal File.binread(File.join(fresh, name)), File.binread(File.join(replay, name)), name }

    lock_path = File.join(@candidate, "sources.lock.json")
    altered = JSON.parse(File.read(lock_path))
    altered.fetch("inputs")[1]["sha256"] = Digest::SHA256.hexdigest("new upstream content")
    File.write(lock_path, JSON.generate(altered))
    _out, error, status = invoke(*refresh, "--output", File.join(@work, "changed"), env: env)
    assert status.success?, error
    assert_includes error, "Changed publisher bytes"
    failed = File.join(@work, "failed")
    _out, error, status = invoke(*replay_args, "--output", failed, env: env)
    refute status.success?
    assert_includes error, "does not match replay lock"
    refute_path_exists failed
    _out, error, status = invoke(*refresh, "--output", failed, env: env.merge("REGION_FIXTURE_OFFLINE" => "1"))
    refute status.success?
    assert_includes error, "fixture download failed"
    refute_path_exists failed
    assert_equal installed_lock, File.binread(File.join(@source, "release", "sources.lock.json"))
    cli("--check")
  end

  def test_another_canadian_vintage_needs_native_topology_pins_for_every_province
    lock = release_lock(ca_year: 2031)
    lock_path = File.join(@candidate, "sources.lock.json")
    report_path = File.join(@candidate, "report.json")
    report = JSON.parse(File.read(report_path))
    report["sourceMembership"] = RegionGenerator::NORMALIZED.keys.to_h { |purpose| [purpose, source_members(ca_year: 2031)] }
    File.write(report_path, JSON.generate(report))
    pin_release_files(lock)
    File.write(lock_path, JSON.generate(lock))
    capture_io { RegionGenerator.new(source: @source, resources: File.join(@candidate, "resources")).run(release: @candidate) }
    cli("--adopt", @candidate)
    assert_equal 60, lock.fetch("inputs").size
    pin = lock.fetch("inputs").find { |row| row.fetch("key") == "statcanCartographic-62-topology" }
    pin["url"] = pin.fetch("url").sub("f=pbf", "f=geojson")
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Wrong publisher URL for statcanCartographic-62-topology"
    lock.fetch("inputs").delete(pin)
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Missing or duplicate release input pins"
    cli("--check")
  end

  def test_adoption_rejects_incomplete_pins_membership_and_provenance_before_installing
    cli("--adopt", @candidate)
    lock_path = File.join(@candidate, "sources.lock.json")
    report_path = File.join(@candidate, "report.json")
    original_lock = File.read(lock_path)
    original_report = File.read(report_path)
    mutations = {
      "duplicate release input pins" => ->(lock, _) { lock["inputs"].pop },
      "Wrong publisher URL for statcanDigital-62" => ->(lock, _) { lock["inputs"].find { |p| p["key"] == "statcanDigital-62" }["url"] += "&maxAllowableOffset=50" },
      "Wrong publisher URL for statcanDigital-35" => ->(lock, _) { lock["inputs"].find { |p| p["key"] == "statcanDigital-35" }["url"] += "&geometryPrecision=7" },
      "Invalid checksum or size" => ->(lock, _) { lock["inputs"].first["bytes"] = 0 },
      "Wrong publisher URL" => ->(lock, _) { lock["inputs"][1]["url"] = "https://example.com/service" },
      "license" => ->(lock, _) { lock["sources"]["statcanDigital"].delete("license") },
      "GEOS" => ->(lock, _) { lock["toolchain"].delete("GEOS") },
      "Expected all four source products" => ->(lock, _) { lock["sources"].delete("censusCartographic") },
      "Incorrect WGS84 or tracking simplification settings" => ->(lock, _) { lock["conversion"]["tracking"]["maximumDisplacementMetres"] = 26 },
      "trackingAccuracy" => ->(_, report) { report.delete("trackingAccuracy") },
      "Incorrect tracking displacement cap" => ->(_, report) { report["trackingAccuracy"]["capMetres"] = 50 },
      "Incorrect source hashes for us-NY" => ->(_, report) { report["trackingAccuracy"]["members"]["us-NY"]["sourceSHA256"]["censusTIGER-state"] = "0" * 64 },
      "Incorrect source hashes for ca-ON" => ->(_, report) { report["trackingAccuracy"]["members"]["ca-ON"]["sourceSHA256"].delete("statcanDigital-35-topology") },
      "Incorrect source hashes for ca-QC" => ->(_, report) {
        members = report["trackingAccuracy"]["members"]
        members["ca-QC"]["sourceSHA256"] = members["ca-ON"]["sourceSHA256"]
      },
      "certificate membership differs" => ->(_, report) { report["trackingAccuracy"]["members"].delete("ca-ON") },
      "Tracking certificate membership" => ->(_, report) { report["trackingAccuracy"]["members"]["european-union"] = {} },
      "Invalid tracking accuracy certificate for ca-ON" => ->(_, report) { report["trackingAccuracy"]["members"]["ca-ON"]["upperBoundMetres"] = 25.001 },
      "Tracking geometry for ca-ON differs from the certified TWKB" => ->(_, report) { report["trackingAccuracy"]["members"]["ca-ON"]["sha256"] = "0" * 64 },
      "Incorrect maximum tracking" => ->(_, report) { report["trackingAccuracy"]["maximumUpperBoundMetres"] = 12.0 },
      "Invalid US source inventory" => ->(_, report) { report["sourceMembership"].fetch("display").reject! { |r| r["STUSPS"] == "GU" } },
      "Invalid Canadian source member" => ->(_, report) { report["sourceMembership"].fetch("tracking").last["catalogID"] = "ca-ON" },
    }
    mutations.each do |diagnostic, mutate|
      lock = JSON.parse(original_lock)
      report = JSON.parse(original_report)
      mutate.call(lock, report)
      File.write(report_path, JSON.generate(report))
      lock.fetch("report")["sha256"] = Digest::SHA256.file(report_path).hexdigest
      File.write(lock_path, JSON.generate(lock))
      _out, error, status = invoke("--adopt", @candidate)
      refute status.success?
      assert_includes error, diagnostic
      refute File.exist?(File.join(@root, ".region-adoption"))
    end
    cli("--check")
  end

  def test_failed_commit_restores_previous_install_before_retry
    cli("--adopt", @candidate)
    prior_manifest = File.binread(File.join(@resources, "regions.json"))
    prior_geometry = File.binread(File.join(@resources, "regions/ca/ca-ON.tracking.twkb"))
    original = JSON.parse(Zlib::GzipReader.open(File.join(@candidate, "north-america.geojson.gz"), &:read))
    original.fetch("features").first.fetch("properties")["name"] = "Updated state name"
    normalized = File.join(@candidate, "north-america.geojson.gz")
    Zlib::GzipWriter.open(normalized) { |gz| gz.write(JSON.generate(original)) }
    lock_path = File.join(@candidate, "sources.lock.json")
    lock = JSON.parse(File.read(lock_path))
    lock.fetch("normalized").fetch("tracking")["sha256"] = Digest::SHA256.file(normalized).hexdigest
    File.write(lock_path, JSON.generate(lock))
    capture_io { RegionGenerator.new(source: @source, resources: File.join(@candidate, "resources")).run(release: @candidate) }
    failing = Class.new(RegionRelease::InstallTransaction) do
      def after_apply(index)
        raise Errno::ENOSPC if index == 1
      end
    end
    capture_io do
      assert_raises(Errno::ENOSPC) { RegionRelease.new(root: @root, transaction: failing).run(["--adopt", @candidate]) }
    end
    assert_equal prior_manifest, File.binread(File.join(@resources, "regions.json"))
    assert_equal prior_geometry, File.binread(File.join(@resources, "regions/ca/ca-ON.tracking.twkb"))
    cli("--adopt", @candidate)
    cli("--check")
  end

  private

  def invoke(*args, env: {})
    Open3.capture3(env, RbConfig.ruby, File.join(@tools, "generate-regions.rb"), *args)
  end

  def cli(*args)
    out, error, status = invoke(*args)
    assert status.success?, "#{out}\n#{error}"
  end

  def make_candidate
    geometry = { "type" => "Polygon", "coordinates" => [[[0, 0], [0, 1], [1, 1], [0, 0]]] }
    data = []
    US_TRACKING_CODES.each do |code|
      kind = { "DC" => "federalDistrict", "PR" => "territory" }.fetch(code, "state")
      data << ["us-#{code}", kind, "united-states"]
    end
    RegionRelease::PROVINCES.each do |code|
      data << ["ca-#{code}", %w[NT NU YT].include?(code) ? "territory" : "province", "canada"]
    end
    RegionGenerator::NORMALIZED.each do |purpose, filename|
      features = data.map do |id, kind, parent|
        properties = { "id" => id, "name" => id, "kind" => kind, "isLoggable" => true,
                       "source" => RegionGenerator::PRODUCTS.fetch(parent).fetch(purpose), "parentID" => parent }
        { "type" => "Feature", "properties" => properties, "geometry" => geometry }
      end
      Zlib::GzipWriter.open(File.join(@candidate, filename)) do |gz|
        gz.write(JSON.generate("type" => "FeatureCollection", "features" => features))
      end
    end
    lock = release_lock
    encoded_sha = Digest::SHA256.hexdigest(TinyWKB.encode(geometry))
    pins = lock.fetch("inputs").to_h { |pin| [pin.fetch("key"), pin.fetch("sha256")] }
    members = source_members.select { |row| row.fetch("catalogID") }.to_h do |row|
      keys = row["PRUID"] ? ["statcanDigital-#{row["PRUID"]}", "statcanDigital-#{row["PRUID"]}-topology"] : ["censusTIGER-state"]
      [row.fetch("catalogID"), { "sourceSHA256" => pins.slice(*keys), "sha256" => encoded_sha, "upperBoundMetres" => 0.0 }]
    end
    certificate = {
      "capMetres" => 25, "maximumUpperBoundMetres" => 0.0, "members" => members,
    }
    report = { "trackingAccuracy" => certificate, "sourceMembership" => RegionGenerator::NORMALIZED.keys.to_h { |p| [p, source_members] } }
    File.write(File.join(@candidate, "report.json"), JSON.generate(report))
    pin_release_files(lock)
    File.write(File.join(@candidate, "sources.lock.json"), JSON.generate(lock))
    gen = RegionGenerator.new(source: @source, resources: File.join(@candidate, "resources"))
    capture_io { gen.run(release: @candidate) }
  end

  def source_members(ca_year: 2026)
    states = (US_TRACKING_CODES + %w[AS GU MP VI]).each_with_index.map do |code, index|
      fips = format("%02d", index + 1)
      { "countryID" => "united-states", "GEOID" => fips, "STATEFP" => fips, "STUSPS" => code,
        "catalogID" => (US_TRACKING_CODES.include?(code) ? "us-#{code}" : nil) }
    end
    states + RegionRelease::CANADA_CODES.map do |uid, code|
      { "countryID" => "canada", "PRUID" => uid, "postalCode" => code, "DGUID" => "#{ca_year}A0002#{uid}", "catalogID" => "ca-#{code}" }
    end
  end

  def pin_release_files(lock)
    pin = ->(file) { { "file" => file, "sha256" => Digest::SHA256.file(File.join(@candidate, file)).hexdigest } }
    lock["normalized"] = RegionGenerator::NORMALIZED.transform_values(&pin)
    lock["report"] = pin.call("report.json")
  end

  def release_lock(ca_year: 2026)
    urls = {
      "censusTIGER-state" => "https://www2.census.gov/geo/tiger/TIGER2026/STATE/tl_2026_us_state.zip",
      "censusCartographic-state" => "https://www2.census.gov/geo/tiger/GENZ2025/shp/cb_2025_us_state_500k.zip",
    }
    RegionRelease::STATCAN_SERVICES.each do |product, basename|
      service = "https://geo.statcan.gc.ca/geo_wa/rest/services/#{ca_year}/#{basename}/MapServer"
      urls["#{product}-service"] = "#{service}?f=pjson"
      urls["#{product}-layer"] = "#{service}/0?f=pjson"
      urls["#{product}-inventory"] = "#{service}/0/query?where=1%3D1&returnGeometry=false&f=geojson&outFields=PRUID%2CDGUID%2CPRENAME%2CPRFNAME&orderByFields=PRUID"
      RegionRelease::CANADA_CODES.each_key do |uid|
        query = "#{service}/0/query?where=PRUID%3D%27#{uid}%27&returnGeometry=true"
        geometry_url = "#{query}&outSR=4326&f=geojson&outFields=PRUID%2CDGUID%2CPRENAME%2CPRFNAME"
        geometry_url += "&geometryPrecision=7" if product == "statcanCartographic"
        urls["#{product}-#{uid}"] = geometry_url
        urls["#{product}-#{uid}-topology"] = "#{query}&outFields=PRUID&outSR=3347&f=pbf" if product == "statcanDigital" || ca_year != 2026
      end
    end
    source = { "product" => "fixture", "publisher" => "publisher", "includes" => "polygons", "license" => "fixture" }
    years = { "usYear" => 2026, "usDisplayYear" => 2025, "caYear" => ca_year }
    {
      **years, "version" => 4, "sources" => RegionGenerator::YEARS.transform_values { |key| source.merge("referenceDate" => "#{years.fetch(key)}-01-01") },
      "toolchain" => { "python" => "3.12", "GEOS" => "3", "PROJ" => "9", "projectionDatabaseSHA256" => "a" * 64,
                       "projectionNetworkEnabled" => false, "packages" => %w[numpy pyproj pyshp shapely certifi].to_h { |name| [name, "1.0"] } },
      "conversion" => { "algorithm" => "simplify", "winding" => "CCW", "coordinateDecimals" => 7,
                        "tracking" => { "initialToleranceMetres" => 180, "maximumDisplacementMetres" => 25, "restorationMethod" => "adaptive" },
                        "canadianNearDuplicateToleranceMetres" => 0.02, "usDisplay" => { "toleranceMetres" => 0 }, "caDisplay" => { "toleranceMetres" => 180 },
                        "normalizedEPSG" => 4326, "usSourceEPSG" => 4269, "canadianProjection" => 3347,
                        "usProjections" => { "continental" => 5070, "AK" => 3338, "HI" => 26963, "PR" => 32161 },
                        "canadianRequest" => { "outSR" => 4326, "displayGeometryPrecision" => 7, "serverReprojects" => true } },
      "inputs" => urls.map { |key, url| { "key" => key, "url" => url, "bytes" => 42, "sha256" => Digest::SHA256.hexdigest(key) } },
    }
  end
end
