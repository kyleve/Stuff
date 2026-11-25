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
    us = File.join(@resources, "regions/us-CA.twkb")
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

  def test_adoption_removes_superseded_country_resources_and_rejects_the_old_release
    directory = File.join(@resources, "regions")
    FileUtils.mkdir_p(directory)
    %w[canada.twkb united-states.twkb].each { |name| File.write(File.join(directory, name), "old country") }
    cli("--adopt", @candidate)
    names = Dir.children(directory)
    assert_equal 66, names.size
    refute_includes names, "canada.twkb"
    refute_includes names, "united-states.twkb"
    cli("--check")

    stale = File.join(directory, "canada.twkb")
    File.write(stale, "left behind by a previous generator")
    _out, error, status = invoke("--check")
    refute status.success?
    assert_includes error, "differs"
    assert_path_exists stale
    cli
    refute_path_exists stale

    lock_path = File.join(@candidate, "sources.lock.json")
    lock = JSON.parse(File.read(lock_path)).merge("version" => 1)
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Unsupported release lock version"
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
    lock.fetch("normalized")["sha256"] = Digest::SHA256.file(path).hexdigest
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Expected a subdivision"
    refute_path_exists File.join(@resources, "regions.json")
  end

  def test_damaged_candidate_does_not_replace_previous_resources
    cli("--adopt", @candidate)
    file = File.join(@candidate, "resources/regions/ca-ON.twkb")
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
      when "--refresh" then ["--us-year", "2026", "--ca-year", "2026"]
      when "--replay"
        pin = args.first
        abort "fixture cache does not match replay lock" unless File.binread(pin) == File.binread(lock)
        [pin]
      else abort "unexpected mode"
      end
      abort "unexpected converter arguments: #{args.inspect}" unless args == expected + ["--cache", cache, "--output", stage]
      FileUtils.cp(File.join(source, "report.json"), stage)
      abort "fixture download failed" if mode == "--refresh" && ENV["REGION_FIXTURE_OFFLINE"]
      %w[north-america.geojson.gz sources.lock.json].each { |file| FileUtils.cp(File.join(source, file), stage) }
    RUBY
    FileUtils.chmod(0o755, converter)
    cache = File.join(File.realpath(@work), "cache")
    env = { "REGIONKIT_PYTHON" => converter, "REGION_FIXTURE_SOURCE" => @candidate, "REGION_FIXTURE_CACHE" => cache }
    refresh = ["--refresh", "--us-year", "2026", "--ca-year", "2026", "--cache", cache]
    fresh = File.join(@work, "fresh")
    _out, error, status = invoke(*refresh, "--output", fresh, env: env)
    assert status.success?, error
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
    altered.fetch("inputs").first["sha256"] = Digest::SHA256.hexdigest("new upstream content")
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
    report = { "sourceMembership" => source_members(ca_year: 2031) }
    File.write(report_path, JSON.generate(report))
    %w[normalized report].zip(%w[north-america.geojson.gz report.json]).each do |key, file|
      lock[key] = { "file" => file, "sha256" => Digest::SHA256.file(File.join(@candidate, file)).hexdigest }
    end
    File.write(lock_path, JSON.generate(lock))
    capture_io { RegionGenerator.new(source: @source, resources: File.join(@candidate, "resources")).run(release: @candidate) }
    cli("--adopt", @candidate)
    assert_equal 30, lock.fetch("inputs").size
    pin = lock.fetch("inputs").find { |row| row.fetch("key") == "statcan-62-topology" }
    pin["url"] = pin.fetch("url").sub("f=pbf", "f=geojson")
    File.write(lock_path, JSON.generate(lock))
    _out, error, status = invoke("--adopt", @candidate)
    refute status.success?
    assert_includes error, "Wrong publisher URL for statcan-62-topology"
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
      "Invalid checksum or size" => ->(lock, _) { lock["inputs"].first["bytes"] = 0 },
      "Wrong publisher URL" => ->(lock, _) { lock["inputs"][1]["url"] = "https://example.com/service" },
      "license" => ->(lock, _) { lock["sources"]["statcan"].delete("license") },
      "GEOS" => ->(lock, _) { lock["toolchain"].delete("GEOS") },
      "Invalid US source inventory" => ->(_, report) { report["sourceMembership"].reject! { |r| r["STUSPS"] == "GU" } },
      "Invalid Canadian source member" => ->(_, report) { report["sourceMembership"].last["catalogID"] = "ca-ON" },
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
    prior_geometry = File.binread(File.join(@resources, "regions/ca-ON.twkb"))
    original = JSON.parse(Zlib::GzipReader.open(File.join(@candidate, "north-america.geojson.gz"), &:read))
    original.fetch("features").first.fetch("properties")["name"] = "Updated state name"
    normalized = File.join(@candidate, "north-america.geojson.gz")
    Zlib::GzipWriter.open(normalized) { |gz| gz.write(JSON.generate(original)) }
    lock_path = File.join(@candidate, "sources.lock.json")
    lock = JSON.parse(File.read(lock_path))
    lock.fetch("normalized")["sha256"] = Digest::SHA256.file(normalized).hexdigest
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
    assert_equal prior_geometry, File.binread(File.join(@resources, "regions/ca-ON.twkb"))
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
    features = data.map do |id, kind, parent|
      properties = { "id" => id, "name" => id, "kind" => kind, "isLoggable" => true,
                     "source" => parent == "united-states" ? "census" : "statcan" }
      properties["parentID"] = parent if parent
      { "type" => "Feature", "properties" => properties, "geometry" => geometry }
    end
    normalized = "north-america.geojson.gz"
    Zlib::GzipWriter.open(File.join(@candidate, normalized)) do |gz|
      gz.write(JSON.generate("type" => "FeatureCollection", "features" => features))
    end
    File.write(File.join(@candidate, "report.json"), JSON.generate("sourceMembership" => source_members))
    lock = release_lock
    { "normalized" => normalized, "report" => "report.json" }.each do |key, file|
      lock[key] = { "file" => file, "sha256" => Digest::SHA256.file(File.join(@candidate, file)).hexdigest }
    end
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

  def release_lock(ca_year: 2026)
    service = "https://geo.statcan.gc.ca/geo_wa/rest/services/#{ca_year}/Cartographic_boundary_files/MapServer"
    urls = {
      "census-state" => "https://www2.census.gov/geo/tiger/TIGER2026/STATE/tl_2026_us_state.zip",
      "statcan-service" => "#{service}?f=pjson", "statcan-layer" => "#{service}/0?f=pjson",
      "statcan-inventory" => "#{service}/0/query?where=1%3D1&returnGeometry=false&f=geojson",
    }
    RegionRelease::CANADA_CODES.each_key do |uid|
      query = "#{service}/0/query?where=PRUID%3D%27#{uid}%27&returnGeometry=true"
      urls["statcan-#{uid}"] = "#{query}&outSR=4326&f=geojson"
      urls["statcan-#{uid}-topology"] = "#{query}&outFields=PRUID&outSR=3347&f=pbf" unless ca_year == 2026
    end
    source = { "product" => "fixture", "publisher" => "publisher", "includes" => "polygons", "license" => "fixture", "referenceDate" => "2026-01-01" }
    {
      "version" => 2, "usYear" => 2026, "caYear" => ca_year, "sources" => { "census" => source, "statcan" => source.merge("referenceDate" => "#{ca_year}-01-01") },
      "toolchain" => { "python" => "3.12", "GEOS" => "3", "PROJ" => "9", "projectionDatabaseSHA256" => "a" * 64,
                       "projectionNetworkEnabled" => false, "packages" => %w[numpy pyproj pyshp shapely certifi].to_h { |name| [name, "1.0"] } },
      "conversion" => { "algorithm" => "simplify", "winding" => "CCW", "coordinateDecimals" => 7, "toleranceMetres" => 180,
                        "normalizedEPSG" => 4326, "canadianRequest" => { "outSR" => 4326 } },
      "inputs" => urls.map { |key, url| { "key" => key, "url" => url, "bytes" => 42, "sha256" => Digest::SHA256.hexdigest(key) } },
    }
  end
end
