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
    _, error, status = Open3.capture3("git", "init", "-q", @root)
    raise error unless status.success?
    File.write(File.join(@root, "AGENTS.md"), "# Root\n")
    FileUtils.cp(File.join(REPOSITORY, "sync-agents"), @root)
    %w[repository file_transaction agent_skill agent_skill_installer agent_files agent_markdown agent_guidance].each do |name|
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

  def test_check_is_read_only_and_reports_optional_absent_installations
    FileUtils.rm_r(File.dirname(@skill))
    before = snapshot
    stdout, stderr, status = run_command("--check")
    assert_predicate status, :success?, stderr
    assert_empty stderr
    assert_includes stdout, "checks passed"
    assert_includes stdout, "External skills absent (layout checks skipped): example"
    assert_includes stdout, "Generated mirrors absent (allowed)"
    assert_equal before, snapshot
    refute_path_exists File.join(@root, ".claude")
    refute_path_exists File.join(@root, "CLAUDE.md")
  end

  def test_check_fails_on_invalid_installed_guidance_without_repairing_it
    before = snapshot
    stdout, stderr, status = run_command("--check")
    assert_equal 1, status.exitstatus
    assert_includes stderr, "missing YAML frontmatter"
    assert_includes stdout, "checks failed"
    assert_equal before, snapshot
  end

  def test_check_rejects_every_mutating_combination_before_work
    before = snapshot
    [["--install"], ["--update"], ["--add", "https://github.com/owner/repo"], ["--git-add"]].each do |arguments|
      stdout, stderr, status = run_command("--check", *arguments)
      assert_equal 1, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "--check cannot be combined"
    end
    assert_equal before, snapshot
  end

  private

  def run_command(*arguments)
    Open3.capture3(RbConfig.ruby, File.join(@root, "sync-agents"), *arguments, chdir: Dir.tmpdir)
  end

  def snapshot
    Dir.glob(File.join(@root, "**", "*"), File::FNM_DOTMATCH).reject { |path| File.directory?(path) }.to_h do |path|
      [path, [File.binread(path), File.stat(path).mtime, File.stat(path).mode]]
    end
  end
end
