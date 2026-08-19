# frozen_string_literal: true

require "minitest/autorun"
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
