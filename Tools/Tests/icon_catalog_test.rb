# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../icon_catalog", __dir__)

class IconCatalogTest < Minitest::Test
  def test_add_dry_run_validates_every_output_without_mutating
    with_fixture do |fixture|
      before = fixture.snapshot

      message = fixture.catalog.add(
        light: fixture.png,
        name: "Ocean",
        id: "ocean",
        dark: "",
        tinted: "",
        dry_run: true,
      )

      assert_equal %(Would add "Ocean" (id: ocean, asset: AppIconOcean).), message
      assert_equal before, fixture.snapshot
    end
  end

  def test_add_preserves_unknown_manifest_metadata
    with_fixture do |fixture|
      fixture.catalog.add(
        light: fixture.png,
        name: "Ocean",
        id: "ocean",
        dark: fixture.png,
        tinted: fixture.png,
        dry_run: false,
      )

      manifest = JSON.parse(File.read(fixture.manifest))
      assert_equal 3, manifest.fetch("formatVersion")
      assert_equal({ "contrast" => "high" }, manifest.fetch("icons").first.fetch("extensionMetadata"))
      assert_equal "AppIconOcean", manifest.fetch("icons").last.fetch("alternateIconName")
      assert_path_exists File.join(fixture.app_catalog, "AppIconOcean.appiconset", "AppIconOcean-Tinted.png")
      assert_path_exists File.join(fixture.preview_catalog, "AppIconOcean.imageset", "AppIconOcean-Dark.png")
    end
  end

  def test_mid_commit_failure_restores_catalogs_and_manifest
    3.times do |fail_after|
      with_fixture(transaction_factory: -> { FailingTransaction.new(fail_after: fail_after) }) do |fixture|
        before = fixture.snapshot

        error = assert_raises(RuntimeError) do
          fixture.catalog.add(
            light: fixture.png,
            name: "Ocean",
            id: "ocean",
            dark: "",
            tinted: "",
            dry_run: false,
          )
        end

        assert_equal "injected commit failure", error.message
        assert_equal before, fixture.snapshot
        assert_empty Dir[File.join(fixture.root, ".icons-stage-*")]
      end
    end
  end

  def test_remove_failure_after_each_boundary_restores_every_catalog
    3.times do |fail_after|
      with_fixture(transaction_factory: -> { FailingTransaction.new(fail_after: fail_after) }) do |fixture|
        fixture.add_existing_ocean
        before = fixture.snapshot

        assert_raises(RuntimeError) { fixture.catalog.remove(target: "ocean", dry_run: false) }

        assert_equal before, fixture.snapshot
        assert_empty Dir[File.join(fixture.root, ".icons-stage-*")]
      end
    end
  end

  def test_remove_dry_run_and_commit_share_the_same_plan
    with_fixture do |fixture|
      fixture.add_existing_ocean
      before = fixture.snapshot

      message = fixture.catalog.remove(target: "ocean", dry_run: true)
      assert_equal %(Would remove "Ocean" (id: ocean).), message
      assert_equal before, fixture.snapshot

      message = fixture.catalog.remove(target: "AppIconOcean", dry_run: false)
      assert_equal %(Removed "Ocean" (id: ocean).), message
      refute_path_exists File.join(fixture.app_catalog, "AppIconOcean.appiconset")
      refute_path_exists File.join(fixture.preview_catalog, "AppIconOcean.imageset")
      manifest = JSON.parse(File.read(fixture.manifest))
      assert_equal ["classic"], manifest.fetch("icons").map { |icon| icon.fetch("id") }
      assert_equal({ "contrast" => "high" }, manifest.fetch("icons").first.fetch("extensionMetadata"))
    end
  end

  def test_rejects_invalid_png_before_creating_staging_output
    with_fixture do |fixture|
      invalid = File.join(fixture.root, "invalid.png")
      File.write(invalid, "not a png")

      error = assert_raises(IconCatalog::Error) do
        fixture.catalog.add(light: invalid, name: "Bad", id: "bad", dark: "", tinted: "", dry_run: false)
      end

      assert_includes error.message, "not a PNG"
      assert_empty Dir[File.join(fixture.root, ".icons-stage-*")]
    end
  end

  def test_rejects_truncated_and_wrong_size_pngs_before_mutating
    with_fixture do |fixture|
      before = fixture.snapshot
      truncated = File.join(fixture.root, "truncated.png")
      wrong_size = File.join(fixture.root, "wrong-size.png")
      File.binwrite(truncated, "\x89PNG\r\n\x1A\n".b)
      File.binwrite(wrong_size, "\x89PNG\r\n\x1A\n".b + ("\0" * 8) + [512, 1024].pack("NN"))

      truncated_error = assert_raises(IconCatalog::Error) do
        fixture.catalog.add(light: truncated, name: "Bad", id: "bad", dark: "", tinted: "", dry_run: false)
      end
      size_error = assert_raises(IconCatalog::Error) do
        fixture.catalog.add(light: wrong_size, name: "Bad", id: "bad", dark: "", tinted: "", dry_run: false)
      end

      assert_includes truncated_error.message, "not a PNG"
      assert_includes size_error.message, "512x1024"
      assert_equal before.merge("truncated.png" => File.binread(truncated), "wrong-size.png" => File.binread(wrong_size)), fixture.snapshot
    end
  end

  def test_rejects_symlinked_catalog_boundary_without_mutating
    Dir.mktmpdir do |directory|
      real_catalog = File.join(directory, "real-app-catalog")
      linked_catalog = File.join(directory, "linked-app-catalog")
      FileUtils.mkdir_p(real_catalog)
      File.symlink(real_catalog, linked_catalog)
      fixture = Fixture.new(directory, transaction_factory: -> { FileTransaction.new }, app_catalog: linked_catalog)
      before = fixture.snapshot

      error = assert_raises(FileTransaction::Error) do
        fixture.catalog.add(light: fixture.png, name: "Ocean", id: "ocean", dark: "", tinted: "", dry_run: false)
      end

      assert_includes error.message, "parent is a symlink"
      assert_equal before, fixture.snapshot
    end
  end

  def test_staging_write_failure_leaves_every_destination_unchanged
    with_fixture do |fixture|
      before = fixture.snapshot
      real_write = File.method(:write)

      File.stub(:write, lambda { |path, *arguments|
        raise Errno::EACCES, path if File.basename(path) == "Contents.json"

        real_write.call(path, *arguments)
      }) do
        assert_raises(Errno::EACCES) do
          fixture.catalog.add(light: fixture.png, name: "Ocean", id: "ocean", dark: "", tinted: "", dry_run: false)
        end
      end

      assert_equal before, fixture.snapshot
      assert_empty Dir[File.join(fixture.root, ".icons-stage-*")]
    end
  end

  private

  def with_fixture(transaction_factory: -> { FileTransaction.new })
    Dir.mktmpdir do |directory|
      yield Fixture.new(directory, transaction_factory: transaction_factory)
    end
  end

  class FailingTransaction < FileTransaction
    def initialize(fail_after:)
      super()
      @fail_after = fail_after
    end

    protected

    def after_apply(index)
      raise "injected commit failure" if index == @fail_after
    end
  end

  class Fixture
    attr_reader :root, :app_catalog, :preview_catalog, :manifest, :png, :catalog

    def initialize(root, transaction_factory:, app_catalog: nil)
      @root = root
      @app_catalog = app_catalog || File.join(root, "AppIcon.xcassets")
      @preview_catalog = File.join(root, "AppIconPreviews.xcassets")
      @manifest = File.join(root, "AppIcons.json")
      @png = File.join(root, "icon.png")
      FileUtils.mkdir_p([@app_catalog, @preview_catalog])
      File.binwrite(png, "\x89PNG\r\n\x1A\n".b + ("\0" * 8) + [1024, 1024].pack("NN"))
      File.write(manifest, JSON.pretty_generate(
        "formatVersion" => 3,
        "icons" => [{
          "id" => "classic",
          "displayName" => "Classic",
          "alternateIconName" => nil,
          "previewImageName" => "AppIconClassic",
          "extensionMetadata" => { "contrast" => "high" },
        }],
      ) + "\n")
      @catalog = IconCatalog.new(
        root: root,
        app_catalog: @app_catalog,
        preview_catalog: @preview_catalog,
        manifest: @manifest,
        transaction_factory: transaction_factory,
      )
    end

    def add_existing_ocean
      app = File.join(app_catalog, "AppIconOcean.appiconset")
      preview = File.join(preview_catalog, "AppIconOcean.imageset")
      FileUtils.mkdir_p([app, preview])
      File.write(File.join(app, "marker"), "app")
      File.write(File.join(preview, "marker"), "preview")
      data = JSON.parse(File.read(manifest))
      data.fetch("icons") << {
        "id" => "ocean",
        "displayName" => "Ocean",
        "alternateIconName" => "AppIconOcean",
        "previewImageName" => "AppIconOcean",
      }
      File.write(manifest, JSON.pretty_generate(data) + "\n")
    end

    def snapshot
      Dir[File.join(root, "**", "*")].sort.to_h do |path|
        relative = path.delete_prefix("#{root}/")
        [relative, File.directory?(path) ? :directory : File.binread(path)]
      end
    end
  end
end
