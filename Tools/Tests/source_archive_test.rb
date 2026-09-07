# frozen_string_literal: true

require "digest"
require "minitest/autorun"
require "tmpdir"

require_relative "../../Throw/ThrowCore/Tools/geography/source_archive"

class GeographySourceArchiveTest < Minitest::Test
  def test_reads_exact_members_from_a_digest_pinned_zip
    Dir.mktmpdir("throw-geography-source") do |directory|
      archive_path = write_zip(directory, "roads.shp" => "shape", "roads.dbf" => "table")
      archive = source_archive(directory, archive_path)

      assert_equal ["shape", "table"], archive.shapefile_members
    end
  end

  def test_rejects_an_archive_with_an_unexpected_digest
    Dir.mktmpdir("throw-geography-source") do |directory|
      archive_path = write_zip(directory, "roads.shp" => "shape", "roads.dbf" => "table")
      specification = archive_specification(archive_path).merge("sha256" => "0" * 64)

      error = assert_raises(ThrowGeography::SourceError) do
        ThrowGeography::SourceArchive.new(
          source_directory: directory,
          specification: specification,
        ).verified_path
      end

      assert_includes error.message, "Unexpected SHA-256"
    end
  end

  def test_rejects_a_zip_without_the_pinned_member
    Dir.mktmpdir("throw-geography-source") do |directory|
      archive_path = write_zip(directory, "roads.shp" => "shape")
      archive = source_archive(directory, archive_path)

      error = assert_raises(ThrowGeography::SourceError) { archive.shapefile_members }

      assert_includes error.message, "roads.dbf"
    end
  end

  private

  def source_archive(directory, path)
    ThrowGeography::SourceArchive.new(
      source_directory: directory,
      specification: archive_specification(path),
    )
  end

  def archive_specification(path)
    {
      "file" => File.basename(path),
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "members" => { "shp" => "roads.shp", "dbf" => "roads.dbf" },
    }
  end

  def write_zip(directory, members)
    members.each { |name, contents| File.binwrite(File.join(directory, name), contents) }
    archive_path = File.join(directory, "roads.zip")
    success = system("zip", "-q", archive_path, *members.keys, chdir: directory)
    raise "zip command failed" unless success

    archive_path
  end
end
