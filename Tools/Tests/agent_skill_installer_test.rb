# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../agent_skill_installer"

class AgentSkillInstallerTest < Minitest::Test
  class CopyFailure < AgentSkillInstaller
    def copy(source, destination, exclusions:)
      super
      raise IOError, "copy failed"
    end
  end

  class CommitFailure < FileTransaction
    def after_apply(index)
      raise IOError, "replacement failed" if index == 1
    end
  end

  class FailingInstaller < AgentSkillInstaller
    def make_transaction
      CommitFailure.new
    end
  end

  def setup
    @root = Dir.mktmpdir("skill install ü ")
    @checkout = File.join(@root, "upstream")
    @source = File.join(@checkout, "example")
    @destination = File.join(@root, "installed", "example")
    @manifest = File.join(@root, "manifest.json")
    [@source, @destination].each { |directory| FileUtils.mkdir_p(directory) }
    File.write(File.join(@source, "SKILL.md"), "---\nname: example\ndescription: Test\n---\n")
    File.write(File.join(@destination, "old"), "previous installation")
    File.write(@manifest, "previous manifest")
    @skill = AgentSkill.new("example", { "repo" => "owner/repo", "path" => "example", "ref" => "123", "exclude" => ["skills", ".claude-plugin"] })
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def install(installer = AgentSkillInstaller.new)
    installer.install(@skill, checkout: @checkout, destination: @destination,
      manifest_update: AgentSkillInstaller::ManifestUpdate.new(path: @manifest, content: "new manifest"))
  end

  def assert_previous_installation
    assert_equal "previous installation", File.read(File.join(@destination, "old"))
    assert_equal "previous manifest", File.read(@manifest)
    assert_empty Dir.glob(File.join(@root, "installed", ".skill-stage-*"))
  end

  def test_exclusions_remove_only_packaging_and_commit_manifest_with_skill
    %w[skills/example .claude-plugin references assets].each { |path| FileUtils.mkdir_p(File.join(@source, path)) }
    FileUtils.cp(File.join(@source, "SKILL.md"), File.join(@source, "skills", "example", "SKILL.md"))
    File.write(File.join(@source, ".claude-plugin", "plugin.json"), "plugin")
    File.write(File.join(@source, "references", "guide.md"), "guide")
    File.binwrite(File.join(@source, "assets", "image.bin"), "\xFF\x00".b)
    install
    assert @skill.installed?(@destination)
    refute_path_exists File.join(@destination, "skills")
    refute_path_exists File.join(@destination, ".claude-plugin")
    assert_equal "guide", File.read(File.join(@destination, "references", "guide.md"))
    assert_equal "\xFF\x00".b, File.binread(File.join(@destination, "assets", "image.bin"))
    assert_equal "new manifest", File.read(@manifest)
  end

  def test_copy_failure_preserves_installation_and_manifest
    assert_raises(IOError) { install(CopyFailure.new) }
    assert_previous_installation
  end

  def test_replacement_failure_rolls_back_both_directory_and_manifest
    assert_raises(IOError) { install(FailingInstaller.new) }
    assert_previous_installation
  end

  def test_invalid_candidate_does_not_replace_existing_skill
    File.write(File.join(@source, "SKILL.md"), "---\nname: wrong\ndescription: Test\n---\n")
    error = assert_raises(AgentSkill::Error) { install }
    assert_includes error.message, "declares"
    assert_previous_installation
    File.unlink(File.join(@source, "SKILL.md"))
    assert_raises(AgentSkill::Error) { install }
    assert_previous_installation
  end

  def test_excluded_symlinks_are_not_followed_and_their_targets_are_preserved
    outside = File.join(@root, "outside")
    FileUtils.mkdir_p(outside)
    File.write(File.join(outside, "keep"), "untouched")
    File.symlink(outside, File.join(@source, "skills"))
    install
    refute_path_exists File.join(@destination, "skills")
    assert_equal "untouched", File.read(File.join(outside, "keep"))
    assert @skill.installed?(@destination)
  end

  def test_symlinks_outside_exclusions_are_rejected
    File.symlink(@destination, File.join(@source, "references"))
    error = assert_raises(AgentSkill::Error) { install }
    assert_includes error.message, "symlink"
    assert_previous_installation
  end
end
