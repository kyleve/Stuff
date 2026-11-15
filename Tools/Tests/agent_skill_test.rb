# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../agent_skill"

class AgentSkillTest < Minitest::Test
  def entry
    { "repo" => "example/skills", "path" => "skills/example", "ref" => "123abc" }
  end

  def test_manifest_rejects_paths_that_escape_or_replace_the_entry_point
    ["", "/tmp/skill", "../skill", "skill/../other", "./skill", "a//b", "a/", "a\\b", "a\0b"].each do |path|
      assert_raises(AgentSkill::Error) { AgentSkill.new("example", entry.merge("path" => path)) }
      assert_raises(AgentSkill::Error) { AgentSkill.new("example", entry.merge("exclude" => [path])) }
    end
    assert_raises(AgentSkill::Error) { AgentSkill.new("example", entry.merge("exclude" => ["SKILL.md"])) }
    assert_raises(AgentSkill::Error) { AgentSkill.new("example", entry.merge("exclude" => "skills")) }
    assert_equal ["skills", ".claude-plugin"], AgentSkill.new("example", entry.merge("exclude" => ["skills", ".claude-plugin"])).exclusions
  end

  def test_metadata_requires_valid_yaml_and_nonempty_name_and_description
    Dir.mktmpdir do |root|
      file = File.join(root, "SKILL.md")
      ["# Example", "---\nname: example\n---\n", "---\nname: example\ndescription: []\n---\n",
       "---\nname: [\n---\n", "---\nname: ../example\ndescription: Test\n---\n"].each do |content|
        File.write(file, content)
        assert_raises(AgentSkill::Error) { AgentSkill.metadata(file) }
      end
      File.write(file, "---\nname: example\ndescription: |\n  Use for a concrete task.\n---\n# Example\n")
      assert_equal "example", AgentSkill.metadata(file).fetch("name")
    end
  end

  def test_installed_layout_rejects_nested_entry_points_wrong_names_and_symlinks
    skill = AgentSkill.new("example", entry)
    Dir.mktmpdir do |root|
      path = File.join(root, "SKILL.md")
      File.write(path, "---\nname: example\ndescription: Test\n---\n")
      assert skill.installed?(root)
      FileUtils.mkdir_p(File.join(root, ".hidden"))
      FileUtils.cp(path, File.join(root, ".hidden", "SKILL.md"))
      refute skill.installed?(root)
      FileUtils.rm_r(File.join(root, ".hidden"))
      File.symlink(path, File.join(root, "alias"))
      refute skill.installed?(root)
      File.unlink(File.join(root, "alias"))
      File.write(path, "---\nname: other\ndescription: Test\n---\n")
      refute skill.installed?(root)
    end
  end
end
