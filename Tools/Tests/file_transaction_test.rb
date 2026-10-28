# frozen_string_literal: true

require "minitest/autorun"
require "ostruct"
require "tmpdir"

require File.expand_path("../file_transaction", __dir__)

class FileTransactionTest < Minitest::Test
  def test_commits_replacements_and_removals
    Dir.mktmpdir do |directory|
      replace = File.join(directory, "replace")
      remove = File.join(directory, "remove")
      staged = File.join(directory, "staged")
      File.write(replace, "old")
      File.write(remove, "delete")
      File.write(staged, "new")

      transaction = FileTransaction.new
      transaction.replace(target: replace, staged: staged)
      transaction.remove(target: remove)
      transaction.commit

      assert_equal "new", File.read(replace)
      refute_path_exists remove
      assert_empty Dir[File.join(directory, ".*.backup-*")]
    end
  end

  def test_rolls_every_target_back_after_a_mid_commit_failure
    Dir.mktmpdir do |directory|
      first = File.join(directory, "first")
      second = File.join(directory, "second")
      staged_first = File.join(directory, "staged-first")
      staged_second = File.join(directory, "staged-second")
      File.write(first, "old-first")
      File.write(second, "old-second")
      File.write(staged_first, "new-first")
      File.write(staged_second, "new-second")

      transaction = FailingTransaction.new(fail_after: 1)
      transaction.replace(target: first, staged: staged_first)
      transaction.replace(target: second, staged: staged_second)

      assert_raises(RuntimeError) { transaction.commit }
      assert_equal "old-first", File.read(first)
      assert_equal "old-second", File.read(second)
      assert_empty Dir[File.join(directory, ".*.backup-*")]
    end
  end

  def test_rolls_back_after_each_apply_boundary
    3.times do |fail_after|
      Dir.mktmpdir do |directory|
        targets = 3.times.map { |index| File.join(directory, "target-#{index}") }
        staged = 3.times.map { |index| File.join(directory, "staged-#{index}") }
        targets.each_with_index { |path, index| File.write(path, "old-#{index}") }
        staged.each_with_index { |path, index| File.write(path, "new-#{index}") }

        transaction = FailingTransaction.new(fail_after: fail_after)
        targets.zip(staged).each { |target, replacement| transaction.replace(target: target, staged: replacement) }

        assert_raises(RuntimeError) { transaction.commit }
        assert_equal ["old-0", "old-1", "old-2"], targets.map { |path| File.read(path) }
        assert_empty Dir[File.join(directory, ".*.backup-*")]
      end
    end
  end

  def test_rejects_invalid_boundaries_before_renaming_anything
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      stage_directory = File.join(directory, "stage")
      FileUtils.mkdir_p(stage_directory)
      staged = File.join(stage_directory, "staged")
      File.write(target, "old")
      File.write(staged, "new")

      missing = FileTransaction.new
      missing.replace(target: target, staged: File.join(directory, "missing"))
      assert_raises(FileTransaction::Error) { missing.commit }

      target_link = File.join(directory, "target-link")
      File.symlink(target, target_link)
      linked_target = FileTransaction.new
      linked_target.replace(target: target_link, staged: staged)
      assert_includes assert_raises(FileTransaction::Error) { linked_target.commit }.message, "target is a symlink"

      staged_link = File.join(directory, "staged-link")
      File.symlink(staged, staged_link)
      linked_stage = FileTransaction.new
      linked_stage.replace(target: target, staged: staged_link)
      assert_includes assert_raises(FileTransaction::Error) { linked_stage.commit }.message, "replacement is a symlink"

      real_parent = File.join(directory, "real-parent")
      linked_parent = File.join(directory, "linked-parent")
      FileUtils.mkdir_p(real_parent)
      File.symlink(real_parent, linked_parent)
      parent_link = FileTransaction.new
      parent_link.replace(target: File.join(linked_parent, "target"), staged: staged)
      assert_includes assert_raises(FileTransaction::Error) { parent_link.commit }.message, "parent is a symlink"

      assert_equal "old", File.read(target)
      assert_equal "new", File.read(staged)
    end
  end

  def test_rejects_cross_filesystem_staging_before_renaming
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      stage_directory = File.join(directory, "stage")
      FileUtils.mkdir_p(stage_directory)
      staged = File.join(stage_directory, "staged")
      File.write(target, "old")
      File.write(staged, "new")
      transaction = FileTransaction.new
      transaction.replace(target: target, staged: staged)
      real_stat = File.method(:stat)

      File.stub(:stat, lambda { |path|
        stat = real_stat.call(path)
        path == stage_directory ? OpenStruct.new(dev: stat.dev + 1) : stat
      }) do
        error = assert_raises(FileTransaction::Error) { transaction.commit }
        assert_includes error.message, "not on the target filesystem"
      end

      assert_equal "old", File.read(target)
      assert_equal "new", File.read(staged)
    end
  end

  def test_surfaces_apply_and_rollback_failures_together
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      staged = File.join(directory, "staged")
      File.write(target, "old")
      File.write(staged, "new")
      transaction = FailingTransaction.new(fail_after: 0)
      transaction.replace(target: target, staged: staged)
      real_rename = File.method(:rename)

      error = File.stub(:rename, lambda { |source, destination|
        if File.basename(source).start_with?(".target.backup-")
          raise Errno::EACCES, source
        end
        real_rename.call(source, destination)
      }) do
        assert_raises(FileTransaction::RollbackError) { transaction.commit }
      end

      assert_includes error.message, "injected commit failure"
      assert_includes error.message, "rollback failed"
      assert_equal "new", File.read(target)
      assert_path_exists Dir[File.join(directory, ".target.backup-*")].fetch(0)
    end
  end

  def test_staged_rename_failure_restores_the_original
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      staged = File.join(directory, "staged")
      File.write(target, "old")
      File.write(staged, "new")
      transaction = FileTransaction.new
      transaction.replace(target: target, staged: staged)
      real_rename = File.method(:rename)

      File.stub(:rename, lambda { |source, destination|
        raise Errno::EACCES, source if source == staged && destination == target

        real_rename.call(source, destination)
      }) do
        assert_raises(Errno::EACCES) { transaction.commit }
      end

      assert_equal "old", File.read(target)
      assert_equal "new", File.read(staged)
      assert_empty Dir[File.join(directory, ".target.backup-*")]
    end
  end

  def test_cleanup_failure_never_rolls_back_an_already_committed_value
    Dir.mktmpdir do |directory|
      target = File.join(directory, "target")
      staged = File.join(directory, "staged")
      File.write(target, "old")
      File.write(staged, "new")
      transaction = FileTransaction.new
      transaction.replace(target: target, staged: staged)

      remove = lambda do |path|
        raise Errno::EACCES, path
      end
      error = FileUtils.stub(:remove_entry, remove) do
        assert_raises(FileTransaction::CleanupError) { transaction.commit }
      end

      assert_includes error.message, "transaction committed"
      assert_equal "new", File.read(target)
      assert_equal 1, Dir[File.join(directory, ".target.backup-*")].length
    end
  end

  class FailingTransaction < FileTransaction
    def initialize(fail_after:)
      super()
      @fail_after = fail_after
    end

    protected

    def after_apply(index)
      raise "injected commit failure" if index == @fail_after
    end
  end

end
