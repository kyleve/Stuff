# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

load File.expand_path("../../sync-agents", __dir__)

class SyncAgentsTest < Minitest::Test
  class LocalUpstream < SyncAgents
    attr_reader :fetches
    attr_accessor :fail_fetch

    def initialize(root, upstream)
      super(repository_root: root)
      @upstream = upstream
      @fetches = []
    end

    private

    def clone_repo(repo, revision, destination)
      @fetches << [repo, revision]
      abort "fetch failed" if fail_fetch
      FileUtils.cp_r(File.join(@upstream, "."), destination)
    end

    def clone_default_branch(repo, destination)
      clone_repo(repo, "HEAD", destination)
    end

    def head_sha(_directory)
      "123abc"
    end
  end

  def with_upstream
    Dir.mktmpdir do |root|
      initialize_repository(root)
      Dir.mktmpdir do |upstream|
        source = File.join(upstream, "example")
        FileUtils.mkdir_p(source)
        File.write(File.join(source, "SKILL.md"), "---\nname: example\ndescription: Test\n---\n")
        manifest = File.join(root, ".agents", "external-skills.json")
        FileUtils.mkdir_p(File.dirname(manifest))
        File.write(manifest, JSON.generate("example" => {
          "repo" => "owner/repo", "path" => "example", "ref" => "123abc", "exclude" => ["skills", ".claude-plugin"],
        }))
        yield root, upstream, LocalUpstream.new(root, upstream)
      end
    end
  end

  def test_install_repairs_nested_existing_skill_at_same_pin_and_is_idempotent
    with_upstream do |root, upstream, command|
      source = File.join(upstream, "example")
      FileUtils.mkdir_p(File.join(source, "skills", "example"))
      FileUtils.cp(File.join(source, "SKILL.md"), File.join(source, "skills", "example", "SKILL.md"))
      destination = File.join(root, ".agents", "skills", "example")
      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp_r(source, destination)
      capture_io { command.run(["--install"]) }
      assert_equal [["owner/repo", "123abc"]], command.fetches
      assert_equal [File.join(destination, "SKILL.md")], Dir.glob(File.join(destination, "**", "SKILL.md"))
      assert_equal "123abc", JSON.parse(File.read(File.join(root, ".agents", "external-skills.json"))).fetch("example").fetch("ref")
      stdout, stderr = capture_io { command.run(["--install"]) }
      assert_empty stdout
      assert_empty stderr
      assert_equal 1, command.fetches.length
    end
  end

  def test_failed_fetch_preserves_existing_skill_and_manifest
    with_upstream do |root, _upstream, command|
      destination = File.join(root, ".agents", "skills", "example")
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "SKILL.md"), "invalid but retained")
      manifest_path = File.join(root, ".agents", "external-skills.json")
      manifest = File.binread(manifest_path)
      command.fail_fetch = true
      capture_io { assert_raises(SystemExit) { command.run(["--install"]) } }
      assert_equal "invalid but retained", File.read(File.join(destination, "SKILL.md"))
      assert_equal manifest, File.binread(manifest_path)
      refute_path_exists File.join(root, ".claude")
    end
  end

  def test_update_repairs_invalid_layout_even_when_revision_is_unchanged
    with_upstream do |root, _upstream, command|
      destination = File.join(root, ".agents", "skills", "example")
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "SKILL.md"), "invalid")
      capture_io { command.run(["--update"]) }
      assert_equal "example", AgentSkill.metadata(File.join(destination, "SKILL.md")).fetch("name")
      assert_equal [["owner/repo", "HEAD"]], command.fetches
    end
  end

  def test_add_uses_same_layout_validation_and_preserves_prior_manifest_on_failure
    with_upstream do |root, upstream, command|
      nested = File.join(upstream, "example", "unexpected")
      FileUtils.mkdir_p(nested)
      FileUtils.cp(File.join(upstream, "example", "SKILL.md"), File.join(nested, "SKILL.md"))
      manifest_path = File.join(root, ".agents", "external-skills.json")
      before = File.binread(manifest_path)
      assert_raises(AgentSkill::Error) { command.run(["--add", "https://github.com/owner/repo", "example"]) }
      assert_equal before, File.binread(manifest_path)
      refute_path_exists File.join(root, ".agents", "skills", "example")
    end
  end

  def test_reconciles_generated_docs_skills_and_external_skill_ignores_in_one_pass
    Dir.mktmpdir do |root|
      initialize_repository(root)
      File.write(File.join(root, "AGENTS.md"), "# Root rules\n")
      FileUtils.mkdir_p(File.join(root, "Feature"))
      File.write(File.join(root, "Feature", "AGENTS.md"), "# Feature rules\n")
      FileUtils.mkdir_p(File.join(root, ".agents"))
      File.write(File.join(root, ".agents", "AGENTS.md"), "# Guidance rules\n")

      FileUtils.mkdir_p(File.join(root, "Old"))
      stale_claude = File.join(root, "Old", "CLAUDE.md")
      File.write(stale_claude, "#{MARKER}\n\n# Stale rules\n")
      FileUtils.mkdir_p(File.join(root, "Notes"))
      manual_claude = File.join(root, "Notes", "CLAUDE.md")
      File.write(manual_claude, "# Hand-maintained\n")

      skill = File.join(root, ".agents", "skills", "local")
      FileUtils.mkdir_p(skill)
      File.write(File.join(skill, "SKILL.md"), "# Local skill\n")
      manifest = File.join(root, ".agents", "external-skills.json")
      File.write(
        manifest,
        JSON.generate(
          "zeta" => { "repo" => "example/zeta", "path" => "zeta", "ref" => "1" },
          "alpha" => { "repo" => "example/alpha", "path" => "alpha", "ref" => "2" },
        ),
      )
      stale_mirror = File.join(root, ".claude", "skills", "stale")
      FileUtils.mkdir_p(stale_mirror)
      File.write(File.join(stale_mirror, "SKILL.md"), "# Stale skill\n")

      capture_io { SyncAgents.new(repository_root: root).run([]) }

      assert_equal "#{MARKER}\n\n# Root rules\n", File.read(File.join(root, "CLAUDE.md"))
      assert_equal "#{MARKER}\n\n# Feature rules\n", File.read(File.join(root, "Feature", "CLAUDE.md"))
      assert_equal "#{MARKER}\n\n# Guidance rules\n", File.read(File.join(root, ".agents", "CLAUDE.md"))
      refute_path_exists stale_claude
      assert_equal "# Hand-maintained\n", File.read(manual_claude)
      assert_equal "# Local skill\n", File.read(File.join(root, ".claude", "skills", "local", "SKILL.md"))
      refute_path_exists stale_mirror

      expected_ignore = <<~IGNORE
        # External skills — fetched via ./sync-agents --install
        /alpha/
        /zeta/
      IGNORE
      source_ignore = File.join(root, ".agents", "skills", ".gitignore")
      mirrored_ignore = File.join(root, ".claude", "skills", ".gitignore")
      assert_equal expected_ignore, File.read(source_ignore)
      assert_equal expected_ignore, File.read(mirrored_ignore)

      stdout, stderr = capture_io { SyncAgents.new(repository_root: root).run([]) }
      assert_empty stdout
      assert_empty stderr
    end
  end

  def test_removes_generated_mirror_when_source_skills_are_absent
    Dir.mktmpdir do |root|
      initialize_repository(root)
      File.write(File.join(root, "AGENTS.md"), "# Rules\n")
      mirror = File.join(root, ".claude", "skills", "old")
      FileUtils.mkdir_p(mirror)
      File.write(File.join(mirror, "SKILL.md"), "# Old\n")

      capture_io { SyncAgents.new(repository_root: root).run([]) }

      refute_path_exists File.join(root, ".claude", "skills")
    end
  end

  def test_sync_and_check_agree_on_ignored_instruction_files
    Dir.mktmpdir do |root|
      initialize_repository(root)
      File.write(File.join(root, "AGENTS.md"), "# Root\n")
      File.write(File.join(root, ".gitignore"), ".local-cache/\nCLAUDE.md\n.claude/\n")
      FileUtils.mkdir_p(File.join(root, ".local-cache"))
      File.write(File.join(root, ".local-cache", "AGENTS.md"), "# Cached\n")
      File.write(File.join(root, ".local-cache", "CLAUDE.md"), "#{MARKER}\n\n# Previously generated\n")
      capture_io { SyncAgents.new(repository_root: root).run([]) }
      refute_path_exists File.join(root, ".local-cache", "CLAUDE.md")
      checker = AgentGuidance.new(root)
      assert checker.check, checker.errors.join("\n")
      stdout, stderr = capture_io { SyncAgents.new(repository_root: root).run([]) }
      assert_empty stdout
      assert_empty stderr
    end
  end

  private

  def initialize_repository(root)
    _, error, status = Open3.capture3("git", "init", "-q", root)
    raise error unless status.success?
  end
end
