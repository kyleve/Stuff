# frozen_string_literal: true

require "minitest/autorun"
require_relative "../agent_compatibility"
require_relative "agent_guidance_test_support"

class AgentCompatibilityTest < Minitest::Test
  include AgentGuidanceTestSupport

  def test_fresh_links_read_current_source_without_resync_and_preserve_manual_instructions
    with_guidance_repository do |root|
      source = write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      manual = write_guidance(root, "Feature/CLAUDE.md", "# Manual\n")
      capture_io { AgentCompatibility.new(root).sync }
      link = File.join(root, ".claude/skills/example")
      assert_equal "../../.agents/skills/example", File.readlink(link)
      File.write(source, "changed canonical content")
      assert_equal File.read(source), File.read(File.join(link, "SKILL.md"))
      assert_equal "# Manual\n", File.read(manual)
      refute_path_exists File.join(root, "CLAUDE.md")
      inode = File.lstat(link).ino
      stdout, stderr = capture_io { AgentCompatibility.new(root).sync }
      assert_empty stdout
      assert_includes stderr, "preserved local Claude instructions"
      assert_equal inode, File.lstat(link).ino
    end
  end

  def test_migrates_matching_binary_copies_and_marked_docs_before_source_updates
    with_guidance_repository do |root|
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      asset = write_guidance(root, ".agents/skills/example/assets/file.bin", "\xFF\x00".b)
      write_guidance(root, ".agents/skills/.gitignore", "/external/\n")
      FileUtils.mkdir_p(File.join(root, ".claude"))
      FileUtils.cp_r(File.join(root, ".agents/skills"), File.join(root, ".claude/skills"))
      generated = ["CLAUDE.md", ".agents/CLAUDE.md", "Old/CLAUDE.md"].map do |path|
        write_guidance(root, path, "#{AgentFiles::MARKER}\n\nOld instructions\n")
      end
      capture_io { AgentCompatibility.new(root).sync { File.binwrite(asset, "updated") } }
      generated.each { |path| refute_path_exists path }
      assert File.symlink?(File.join(root, ".claude/skills/example"))
      assert_equal "updated", File.binread(File.join(root, ".claude/skills/example/assets/file.bin"))
      refute_path_exists File.join(root, ".claude/skills/.gitignore")
    end
  end

  def test_conflicting_or_unknown_content_stops_before_the_install_block_or_cleanup
    ["example", "manual"].each do |name|
      with_guidance_repository do |root|
        write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
        local = write_guidance(root, ".claude/skills/#{name}/SKILL.md", "local edits")
        generated = write_guidance(root, "CLAUDE.md", "#{AgentFiles::MARKER}\n\nOld\n")
        ran_install = false
        error = assert_raises(AgentSkill::Error) { AgentCompatibility.new(root).sync { ran_install = true } }
        assert_includes error.message, ".claude/skills/#{name}: unrecognized or changed local content"
        refute ran_install
        assert_equal "local edits", File.read(local)
        assert_path_exists generated
      end
    end
  end

  def test_linked_parents_are_rejected_without_touching_the_destination
    %w[.agents .agents/skills .claude .claude/skills].each do |parent|
      with_guidance_repository do |root|
        Dir.mktmpdir do |outside|
          sentinel = File.join(outside, "keep")
          File.write(sentinel, "outside")
          path = File.join(root, parent)
          FileUtils.mkdir_p(File.dirname(path))
          File.symlink(outside, path)
          error = assert_raises(AgentSkill::Error) { AgentCompatibility.new(root).sync }
          assert_includes error.message, "expected a directory, not a symlink or file"
          assert_equal "outside", File.read(sentinel)
          assert File.symlink?(path)
        end
      end
    end
  end

  def test_foreign_skill_and_instruction_symlinks_are_never_followed_or_replaced
    with_guidance_repository do |root|
      source = write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      FileUtils.mkdir_p(File.join(root, ".claude/skills"))
      link = File.join(root, ".claude/skills/example")
      File.symlink(File.dirname(source), link)
      error = assert_raises(AgentSkill::Error) { AgentCompatibility.new(root).sync }
      assert_includes error.message, "unrecognized or changed local content"
      assert_equal File.dirname(source), File.readlink(link)
      File.unlink(link)
      marked = write_guidance(root, "keep.md", "#{AgentFiles::MARKER}\n\nKeep\n")
      File.symlink(marked, File.join(root, "CLAUDE.md"))
      capture_io { AgentCompatibility.new(root).sync }
      assert_equal marked, File.readlink(File.join(root, "CLAUDE.md"))
      assert_path_exists marked
    end
  end

  def test_recognized_links_are_removed_when_their_source_skill_is_removed
    with_guidance_repository do |root|
      write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
      capture_io { AgentCompatibility.new(root).sync }
      FileUtils.rm_r(File.join(root, ".agents/skills/example"))
      capture_io { AgentCompatibility.new(root).sync }
      assert_empty Dir.children(File.join(root, ".claude/skills"))
    end
  end

  def test_apply_failure_restores_instruction_and_skill_copies
    [0, 1].each do |boundary|
      with_guidance_repository do |root|
        write_guidance(root, ".agents/skills/example/SKILL.md", skill_text)
        copy = write_guidance(root, ".claude/skills/example/SKILL.md", skill_text)
        generated = write_guidance(root, "CLAUDE.md", "#{AgentFiles::MARKER}\n\nOld\n")
        transaction = FileTransaction.new
        transaction.define_singleton_method(:after_apply) { |index| raise "injected migration failure" if index == boundary }
        FileTransaction.stub(:new, transaction) do
          error = assert_raises(RuntimeError) { AgentCompatibility.new(root).sync }
          assert_equal "injected migration failure", error.message
        end
        assert_equal "#{AgentFiles::MARKER}\n\nOld\n", File.read(generated)
        assert_equal skill_text, File.read(copy)
        refute File.symlink?(File.dirname(copy))
        assert_empty Dir.glob(File.join(root, "**", ".*.backup-*"), File::FNM_DOTMATCH)
      end
    end
  end
end
