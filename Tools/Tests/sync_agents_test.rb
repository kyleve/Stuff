# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

load File.expand_path("../../sync-agents", __dir__)

class SyncAgentsTest < Minitest::Test
  class LocalUpstream < SyncAgents
    attr_reader :fetches

    def initialize(root, upstream)
      super(repository_root: root)
      @upstream = upstream
      @fetches = []
    end

    private

    def clone_repo(repo, revision, destination)
      @fetches << [repo, revision]
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

  def test_update_repairs_invalid_layout_even_when_revision_is_unchanged
    with_upstream do |root, _upstream, command|
      destination = File.join(root, ".agents", "skills", "example")
      FileUtils.mkdir_p(destination)
      File.write(File.join(destination, "SKILL.md"), "invalid")
      FileUtils.mkdir_p(File.join(root, ".claude/skills"))
      FileUtils.cp_r(destination, File.join(root, ".claude/skills/example"))
      capture_io { command.run(["--update"]) }
      assert_equal "example", AgentSkill.metadata(File.join(destination, "SKILL.md")).fetch("name")
      assert_equal [["owner/repo", "HEAD"]], command.fetches
      assert_equal "../../.agents/skills/example", File.readlink(File.join(root, ".claude/skills/example"))
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

  def test_partial_update_can_retry_after_matching_copies_are_migrated
    with_upstream do |root, upstream, command|
      manifest = File.join(root, ".agents/external-skills.json")
      entries = %w[first second].to_h { |name| [name, { "repo" => "owner/#{name}", "path" => name, "ref" => "old" }] }
      File.write(manifest, JSON.generate(entries))
      entries.each_key do |name|
        source = File.join(upstream, name)
        canonical = File.join(root, ".agents/skills", name)
        FileUtils.mkdir_p([source, canonical])
        header = "---\nname: #{name}\ndescription: Test\n---\n"
        File.write(File.join(source, "SKILL.md"), header + "new")
        File.write(File.join(canonical, "SKILL.md"), header + "old")
      end
      FileUtils.mkdir_p(File.join(root, ".claude"))
      FileUtils.cp_r(File.join(root, ".agents/skills"), File.join(root, ".claude/skills"))
      fetch = command.method(:clone_default_branch)
      capture_io do
        command.stub(:clone_default_branch, lambda { |repo, destination|
          raise IOError, "second fetch failed" if repo == "owner/second"
          fetch.call(repo, destination)
        }) do
          error = assert_raises(IOError) { command.run(["--update"]) }
          assert_equal "second fetch failed", error.message
        end
      end
      assert_equal %w[123abc old], JSON.parse(File.read(manifest)).values.map { |entry| entry.fetch("ref") }
      entries.each_key { |name| assert File.symlink?(File.join(root, ".claude/skills", name)) }
      capture_io { command.run(["--update"]) }
      assert_equal %w[123abc 123abc], JSON.parse(File.read(manifest)).values.map { |entry| entry.fetch("ref") }
      entries.each_key { |name| assert File.read(File.join(root, ".claude/skills", name, "SKILL.md")).end_with?("new") }
    end
  end

  def test_links_skills_and_updates_external_ignores_without_creating_instruction_copies
    with_upstream do |root, _upstream, command|
      File.write(File.join(root, "AGENTS.md"), "# Root rules\n")
      capture_io { command.run(["--install"]) }
      assert_equal "../../.agents/skills/example", File.readlink(File.join(root, ".claude/skills/example"))
      refute_path_exists File.join(root, "CLAUDE.md")
      assert_equal "# External skills — fetched via ./sync-agents --install\n/example/\n",
        File.read(File.join(root, ".agents/skills/.gitignore"))
      refute_path_exists File.join(root, ".claude/skills/.gitignore")
    end
  end

  def test_sync_and_check_agree_on_ignored_instruction_files
    Dir.mktmpdir do |root|
      initialize_repository(root)
      File.write(File.join(root, "AGENTS.md"), "# Root\n")
      File.write(File.join(root, ".gitignore"), ".local-cache/\nCLAUDE.md\n.claude/\n")
      FileUtils.mkdir_p(File.join(root, ".local-cache"))
      File.write(File.join(root, ".local-cache", "AGENTS.md"), "# Cached\n")
      File.write(File.join(root, ".local-cache", "CLAUDE.md"), "#{AgentFiles::MARKER}\n\n# Previously generated\n")
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
