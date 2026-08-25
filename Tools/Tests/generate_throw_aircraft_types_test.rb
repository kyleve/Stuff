# frozen_string_literal: true

require "digest"
require "json"
require "minitest/autorun"
require "open3"
require "tmpdir"

require_relative "../../Throw/ThrowCore/Tools/generate-aircraft-types"

class GenerateThrowAircraftTypesTest < Minitest::Test
  def test_generation_is_deterministic_and_keeps_only_required_fields
    Dir.mktmpdir("throw-aircraft-types") do |directory|
      source = File.join(directory, "icao_aircraft_types.json")
      File.binwrite(source, JSON.generate(
        "B738" => { "desc" => "L2J", "wtc" => "M", "operator" => "MUST NOT SHIP" },
        "A109" => { "desc" => "H2T", "wtc" => "L" },
      ))
      archive = File.join(directory, "types.zip")
      _output, error, status = Open3.capture3("zip", "-q", archive, File.basename(source), chdir: directory)
      assert status.success?, error
      expected_digest = Digest::SHA256.file(archive).hexdigest
      output = File.join(directory, "output.json")
      generator = ThrowAircraftTypes::Generator.new(
        archive: archive,
        output: output,
        expected_sha256: expected_digest,
      )

      first = capture_io { generator.run }.first
      first_data = File.binread(output)
      second = capture_io { generator.run }.first

      assert_equal first_data, File.binread(output)
      refute_includes first_data, "MUST NOT SHIP"
      assert_includes first, "Wrote 2 aircraft types"
      assert_includes second, "Wrote 2 aircraft types"
    end
  end

  def test_committed_archive_matches_the_pinned_source_shape
    path = File.expand_path(
      "../../Throw/ThrowCore/Sources/Resources/aircraft-types-v1.json",
      __dir__,
    )
    archive = JSON.parse(File.binread(path))

    assert_equal 1, archive.fetch("version")
    assert_equal "722ec71ad990bd75389a6626d6c3a065b02f2b6d", archive.dig("source", "revision")
    assert_operator archive.fetch("types").length, :>, 2_500
  end
end
