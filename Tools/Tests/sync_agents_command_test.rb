# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../repository"

class SyncAgentsCommandTest < Minitest::Test
  REPOSITORY = Repository.root(__FILE__)

  def setup
    @root = Dir.mktmpdir("sync agents ü ")
    FileUtils.mkdir_p([File.join(@root, ".git"), File.join(@root, "Tools"), File.join(@root, ".agents", "skills", "example")])
    FileUtils.cp(File.join(REPOSITORY, "sync-agents"), @root)
    %w[repository file_transaction agent_skill agent_skill_installer].each do |name|
      FileUtils.cp(File.join(REPOSITORY, "Tools", "#{name}.rb"), File.join(@root, "Tools"))
    end
    @manifest = File.join(@root, ".agents", "external-skills.json")
    File.write(@manifest, JSON.generate("example" => { "repo" => "owner/repo", "path" => "example", "ref" => "123" }))
    @skill = File.join(@root, ".agents", "skills", "example", "SKILL.md")
    File.write(@skill, "old invalid skill")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_fetch_failure_reports_status_and_retains_existing_files
    bin = File.join(@root, "bin")
    FileUtils.mkdir_p(bin)
    git = File.join(bin, "git")
    File.write(git, "#!/bin/sh\ncase \"$*\" in *fetch*) echo 'fixture fetch failure' >&2; exit 7;; esac\n")
    File.chmod(0o755, git)
    before = File.binread(@manifest)
    stdout, stderr, status = Open3.capture3({ "PATH" => "#{bin}:/usr/bin:/bin" }, RbConfig.ruby,
      File.join(@root, "sync-agents"), "--install", chdir: Dir.tmpdir)
    assert_equal 1, status.exitstatus
    assert_empty stdout
    assert_includes stderr, "Failed to fetch owner/repo@123"
    assert_includes stderr, "fixture fetch failure"
    assert_equal before, File.binread(@manifest)
    assert_equal "old invalid skill", File.read(@skill)
    refute_path_exists File.join(@root, ".claude")
  end
end
