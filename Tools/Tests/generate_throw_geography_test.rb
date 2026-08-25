# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../../Throw/ThrowCore/Tools/generate-geography"

class GenerateThrowGeographyTest < Minitest::Test
  def test_real_inputs_regenerate_the_committed_archive_byte_for_byte
    Dir.mktmpdir("throw-geography") do |directory|
      output = File.join(directory, "geography-v1.json")
      generator = ThrowGeography::Generator.new(output: output)

      first = capture_io { generator.run }.first
      first_data = File.binread(output)
      second = capture_io { generator.run }.first
      second_data = File.binread(output)

      assert_equal first_data, second_data
      assert_equal File.binread(ThrowGeography::OUTPUT), first_data
      assert_operator first_data.bytesize, :<=, ThrowGeography::MAXIMUM_OUTPUT_BYTES
      assert_includes first, "Wrote 3774 paths"
      assert_includes second, "Wrote 3774 paths"
    end
  end
end
