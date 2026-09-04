# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../app_installer", __dir__)

class AppInstallerTest < Minitest::Test
  APP_NAME = "Ledger"
  BUNDLE_ID = "com.stuff.ledger"

  def test_process_table_matches_only_the_exact_installed_executable
    executable = "/Applications/Ledger.app/Contents/MacOS/Ledger"
    output = <<~PS
       101 #{executable}
       102 #{executable} --argument
       103 /tmp/Ledger.app/Contents/MacOS/Ledger
       104 #{executable}-helper
       105 /bin/sh #{executable}
    PS

    assert_equal [101, 102], InstalledProcessTable.pids(output: output, executable: executable)
  end

  def test_destination_rejects_relative_paths_symlinks_and_another_app
    Dir.mktmpdir do |directory|
      installer = build_installer
      assert_raises(AppInstaller::Error) { installer.validate_destination("Ledger.app") }

      symlink = File.join(directory, "Ledger.app")
      File.symlink(directory, symlink)
      error = assert_raises(AppInstaller::Error) { installer.validate_destination(symlink) }
      assert_includes error.message, "symlink"
      File.unlink(symlink)

      wrong = make_app(directory, bundle_id: "example.other")
      error = assert_raises(AppInstaller::Error) { installer.validate_destination(wrong) }
      assert_includes error.message, "example.other"
    end
  end

  def test_rejects_missing_malformed_and_symlinked_source_bundles
    Dir.mktmpdir do |directory|
      installer = build_installer
      missing = File.join(directory, "missing", "Ledger.app")
      assert_includes assert_raises(AppInstaller::Error) { installer.validate_app(missing) }.message, "does not exist"

      malformed = File.join(directory, "malformed", "Ledger.app")
      FileUtils.mkdir_p(File.join(malformed, "Contents"))
      File.write(File.join(malformed, "Contents", "Info.plist"), "not a plist")
      assert_includes assert_raises(AppInstaller::Error) { installer.validate_app(malformed) }.message, "couldn't read"

      real = make_app(File.join(directory, "real"))
      linked = File.join(directory, "linked", "Ledger.app")
      FileUtils.mkdir_p(File.dirname(linked))
      File.symlink(real, linked)
      assert_includes assert_raises(AppInstaller::Error) { installer.validate_app(linked) }.message, "symlink"
    end
  end

  def test_copy_failure_preserves_the_installed_app
    Dir.mktmpdir do |directory|
      source_parent = File.join(directory, "source")
      destination_parent = File.join(directory, "destination")
      FileUtils.mkdir_p([source_parent, destination_parent])
      source = make_app(source_parent, marker: "new")
      destination = make_app(destination_parent, marker: "old")

      error = FileUtils.stub(:copy_entry, ->(*) { raise Errno::EIO, "copy" }) do
        assert_raises(AppInstaller::Error) { build_installer.install(source: source, destination: destination) }
      end

      assert_includes error.message, "can't install"
      assert_equal "old", File.read(File.join(destination, "marker"))
      assert_empty Dir[File.join(destination_parent, ".Ledger.install-*")]
      assert_empty Dir[File.join(destination_parent, ".Ledger.app.backup-*")]
    end
  end

  def test_install_stages_validates_and_replaces_the_app
    Dir.mktmpdir do |directory|
      source_parent = File.join(directory, "source")
      destination_parent = File.join(directory, "destination")
      FileUtils.mkdir_p([source_parent, destination_parent])
      source = make_app(source_parent, marker: "new")
      destination = make_app(destination_parent, marker: "old")

      build_installer.install(source: source, destination: destination)

      assert_equal "new", File.read(File.join(destination, "marker"))
      assert_empty Dir[File.join(destination_parent, ".Ledger.install-*")]
      assert_empty Dir[File.join(destination_parent, ".Ledger.app.backup-*")]
    end
  end

  def test_mid_commit_failure_restores_the_installed_app
    Dir.mktmpdir do |directory|
      source_parent = File.join(directory, "source")
      destination_parent = File.join(directory, "destination")
      FileUtils.mkdir_p([source_parent, destination_parent])
      source = make_app(source_parent, marker: "new")
      destination = make_app(destination_parent, marker: "old")
      installer = build_installer(transaction_factory: -> { FailingTransaction.new })

      assert_raises(RuntimeError) { installer.install(source: source, destination: destination) }

      assert_equal "old", File.read(File.join(destination, "marker"))
      assert_empty Dir[File.join(destination_parent, ".Ledger.install-*")]
      assert_empty Dir[File.join(destination_parent, ".Ledger.app.backup-*")]
    end
  end

  private

  def build_installer(transaction_factory: -> { FileTransaction.new })
    AppInstaller.new(
      app_name: APP_NAME,
      bundle_id: BUNDLE_ID,
      transaction_factory: transaction_factory,
    )
  end

  def make_app(parent, bundle_id: BUNDLE_ID, marker: nil)
    app = File.join(parent, "#{APP_NAME}.app")
    contents = File.join(app, "Contents")
    FileUtils.mkdir_p(contents)
    File.write(File.join(contents, "Info.plist"), <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>#{bundle_id}</string></dict></plist>
    PLIST
    File.write(File.join(app, "marker"), marker) if marker
    app
  end

  class FailingTransaction < FileTransaction
    protected

    def after_apply(_index)
      raise "injected commit failure"
    end
  end
end
