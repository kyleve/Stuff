# frozen_string_literal: true

require "json"
require "minitest/autorun"
require_relative "../agent_guidance"
require_relative "agent_guidance_test_support"

class AgentGuidanceTest < Minitest::Test
  include AgentGuidanceTestSupport

  def test_root_budget_counts_utf8_bytes_at_the_exact_boundary
    with_guidance_repository do |root|
      write_guidance(root, "AGENTS.md", "é" * 4096)
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal 8192, checker.largest_chain
      write_guidance(root, "AGENTS.md", "é" * 4096 + "x")
      assert_includes validate_guidance(root).errors.join, "root instruction is 8193 bytes"
    end
  end

  def test_combined_chain_includes_root_and_separators
    with_guidance_repository do |root|
      write_guidance(root, "AGENTS.md", "x" * 8192)
      write_guidance(root, "Feature/AGENTS.md", "x" * 10000)
      write_guidance(root, "Feature/Sources/AGENTS.md", "x" * 10476)
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal 28672, checker.largest_chain
      write_guidance(root, "Feature/Sources/AGENTS.md", "x" * 10476 + "é")
      assert_includes validate_guidance(root).errors.join, "instruction chain is 28674 bytes"
    end
  end

  def test_nonempty_override_replaces_ordinary_instructions_and_empty_override_falls_back
    with_guidance_repository do |root|
      write_guidance(root, "Feature/AGENTS.md", "x" * 30000)
      write_guidance(root, "Feature/AGENTS.override.md", "Override")
      write_guidance(root, "Feature/Child/AGENTS.md", "Child")
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal "# Root\n".bytesize + "Override".bytesize + "Child".bytesize + 4, checker.largest_chain
      write_guidance(root, "Feature/AGENTS.override.md", " \n")
      assert_includes validate_guidance(root).errors.join, "instruction chain"
    end
  end

  def test_owned_skill_boundary_frontmatter_duplicate_names_and_nested_entry_points
    with_guidance_repository do |root|
      entry = skill_text
      write_guidance(root, ".agents/skills/example/SKILL.md", entry + "x" * (12288 - entry.bytesize))
      assert_empty validate_guidance(root).errors
      write_guidance(root, ".agents/skills/example/SKILL.md", entry + "x" * (12289 - entry.bytesize))
      assert_includes validate_guidance(root).errors.join, "skill entry point is 12289 bytes"
      write_guidance(root, ".agents/skills/example/SKILL.md", entry)
      write_guidance(root, ".agents/skills/example/nested/SKILL.md", entry)
      write_guidance(root, ".agents/skills/other/SKILL.md", entry)
      messages = validate_guidance(root).errors.join("\n")
      assert_includes messages, "exactly one root SKILL.md"
      assert_includes messages, "duplicate skill name"
      write_guidance(root, ".agents/skills/other/SKILL.md", "---\nname: [\n---\n")
      assert_includes validate_guidance(root).errors.join, "invalid frontmatter"
    end
  end

  def test_links_and_anchors_are_checked_from_both_skill_locations_without_mirrors
    with_guidance_repository do |root|
      write_guidance(root, ".agents/references/guide.md", "# Guide\n")
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text(body: "[guide](../../references/guide.md#guide)\n"))
      messages = validate_guidance(root).errors.join("\n")
      assert_includes messages, "in Claude mirror"
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text(body: "[guide](../../../.agents/references/guide.md#guide)\n[here](#example)\n# Example\n"))
      assert_empty validate_guidance(root).errors
      write_guidance(root, "AGENTS.md", "[bad](.agents/references/guide.md#absent)\n[missing](gone.md)\n")
      messages = validate_guidance(root).errors.join("\n")
      assert_includes messages, "missing anchor"
      assert_includes messages, "missing local link"
    end
  end

  def test_empty_link_destinations_resolve_to_the_current_document
    with_guidance_repository do |root|
      write_guidance(root, "AGENTS.md", "# Root\n[empty]() [spaces](  ) [fragment](#root)\n")
      assert_empty validate_guidance(root).errors
    end
  end

  def test_external_skills_are_optional_but_present_copies_must_match_the_manifest
    with_guidance_repository do |root|
      manifest = { "example" => { "repo" => "owner/repo", "path" => "example", "ref" => "123", "exclude" => ["skills"] } }
      write_guidance(root, ".agents/external-skills.json", JSON.generate(manifest))
      write_guidance(root, ".agents/skills/.gitignore", "/example/\n")
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal ["example"], checker.missing_external
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      assert_empty validate_guidance(root).errors
      write_guidance(root, ".agents/skills/example/skills/example/SKILL.md", skill_text)
      assert_includes validate_guidance(root).errors.join, "exactly one root SKILL.md"
    end
  end

  def test_present_mirrors_must_match_and_absent_mirrors_are_allowed
    with_guidance_repository do |root|
      write_guidance(root, ".agents/AGENTS.md", "# Guidance\n")
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      write_guidance(root, ".agents/skills/example/assets/pixel.bin", "\xFF".b)
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal 3, checker.missing_mirrors
      write_guidance(root, "CLAUDE.md", "#{AgentFiles::MARKER}\n\n# Root\n")
      write_guidance(root, ".agents/CLAUDE.md", "#{AgentFiles::MARKER}\n\n# Guidance\n")
      FileUtils.mkdir_p(File.join(root, ".claude"))
      FileUtils.cp_r(File.join(root, ".agents", "skills"), File.join(root, ".claude", "skills"))
      assert_empty validate_guidance(root).errors
      write_guidance(root, ".claude/skills/example/assets/pixel.bin", "changed")
      write_guidance(root, "CLAUDE.md", "old")
      write_guidance(root, "Old/CLAUDE.md", "#{AgentFiles::MARKER}\n\nOld")
      messages = validate_guidance(root).errors.join("\n")
      assert_includes messages, "stale generated mirror"
      assert_includes messages, "stale skill mirror"
      assert_includes messages, "orphan generated mirror"
    end
  end

  def test_invalid_utf8_and_symlinked_guidance_fail_with_diagnostics
    with_guidance_repository do |root|
      write_guidance(root, "Feature/AGENTS.md", "\xFF".b)
      File.symlink(File.join(root, "AGENTS.md"), File.join(root, "AGENTS.override.md"))
      messages = validate_guidance(root).errors.join("\n")
      assert_includes messages, "invalid UTF-8"
      assert_includes messages, "not a symlink"
    end
  end

  def test_ignored_dependencies_and_markdown_templates_are_outside_guidance_checks
    with_guidance_repository do |root|
      write_guidance(root, "node_modules/vendor/AGENTS.md", "x" * 50000)
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text(body: "[template](assets/plan.md)"))
      write_guidance(root, ".agents/skills/example/assets/plan.md", "[placeholder](NN-step.md)\n")
      checker = validate_guidance(root)
      assert_empty checker.errors
      assert_equal 1, checker.instruction_count
    end
  end
end
