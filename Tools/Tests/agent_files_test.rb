# frozen_string_literal: true

require "minitest/autorun"
require_relative "../agent_files"
require_relative "agent_guidance_test_support"

class AgentFilesTest < Minitest::Test
  include AgentGuidanceTestSupport

  def test_inventory_includes_hidden_and_untracked_inputs_but_not_ignored_copies
    with_guidance_repository do |root|
      write_guidance(root, ".agents/AGENTS.md", "# Guidance\n")
      write_guidance(root, "new folder/AGENTS.md", "# New\n")
      write_guidance(root, ".claude/skills/example/SKILL.md", "ignored")
      write_guidance(root, "CLAUDE.md", "ignored")
      assert_equal [".agents/AGENTS.md", ".gitignore", "AGENTS.md", "new folder/AGENTS.md"], AgentFiles.inventory(root)
    end
  end

  def test_generated_file_walk_includes_hidden_guidance_but_prunes_dependency_trees
    with_guidance_repository do |root|
      hidden = write_guidance(root, ".agents/CLAUDE.md", "generated")
      write_guidance(root, "node_modules/example/CLAUDE.md", "dependency")
      write_guidance(root, ".claude/skills/example/CLAUDE.md", "mirror")
      File.symlink(File.join(root, "node_modules"), File.join(root, "linked-dependencies"))
      assert_equal [hidden], AgentFiles.named(root, "CLAUDE.md", exclude: [".claude"])
    end
  end
end
