# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

load File.expand_path("../../sync-agents", __dir__)

class SyncAgentsTest < Minitest::Test
  def test_reconciles_generated_docs_skills_and_external_skill_ignores_in_one_pass
    Dir.mktmpdir do |root|
      File.write(File.join(root, "AGENTS.md"), "# Root rules\n")
      FileUtils.mkdir_p(File.join(root, "Feature"))
      File.write(File.join(root, "Feature", "AGENTS.md"), "# Feature rules\n")

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
      File.write(File.join(root, "AGENTS.md"), "# Rules\n")
      mirror = File.join(root, ".claude", "skills", "old")
      FileUtils.mkdir_p(mirror)
      File.write(File.join(mirror, "SKILL.md"), "# Old\n")

      capture_io { SyncAgents.new(repository_root: root).run([]) }

      refute_path_exists File.join(root, ".claude", "skills")
    end
  end
end
