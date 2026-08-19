# frozen_string_literal: true

require "fileutils"
require "securerandom"

# Atomically replaces or removes several filesystem entries with rollback.
class FileTransaction
  class CleanupError < StandardError; end

  Operation = Struct.new(:target, :staged, keyword_init: true)
  AppliedOperation = Struct.new(:operation, :backup, :installed, keyword_init: true)

  def initialize
    @operations = []
  end

  def replace(target:, staged:)
    add_operation(target: target, staged: staged)
  end

  def remove(target:)
    add_operation(target: target, staged: nil)
  end

  def commit
    validate
    applied = []
    begin
      @operations.each_with_index do |operation, index|
        backup = backup_path(operation.target)
        File.rename(operation.target, backup) if File.exist?(operation.target) || File.symlink?(operation.target)
        entry = AppliedOperation.new(operation: operation, backup: backup, installed: false)
        applied << entry
        if operation.staged
          File.rename(operation.staged, operation.target)
          entry.installed = true
        end
        after_apply(index)
      end
    rescue StandardError
      rollback(applied)
      raise
    end

    cleanup_failures = applied.filter_map do |entry|
      remove_path(entry.backup)
      nil
    rescue StandardError => error
      "#{entry.backup}: #{error.message}"
    end
    return if cleanup_failures.empty?

    raise CleanupError, "transaction committed, but backup cleanup failed: #{cleanup_failures.join('; ')}"
  end

  protected

  def after_apply(_index); end

  private

  def add_operation(target:, staged:)
    @operations << Operation.new(
      target: File.expand_path(target),
      staged: staged && File.expand_path(staged),
    )
  end

  def validate
    targets = @operations.map(&:target)
    raise "transaction contains duplicate targets" unless targets.uniq.length == targets.length

    @operations.each do |operation|
      raise "transaction target parent does not exist: #{operation.target}" unless Dir.exist?(File.dirname(operation.target))
      next unless operation.staged

      raise "staged replacement does not exist: #{operation.staged}" unless File.exist?(operation.staged) || File.symlink?(operation.staged)
      target_device = File.stat(File.dirname(operation.target)).dev
      staged_device = File.stat(File.dirname(operation.staged)).dev
      raise "staged replacement is not on the target filesystem: #{operation.target}" unless target_device == staged_device
    end
  end

  def rollback(applied)
    applied.reverse_each do |entry|
      target = entry.operation.target
      remove_path(target) if entry.installed && (File.exist?(target) || File.symlink?(target))
      File.rename(entry.backup, target) if File.exist?(entry.backup) || File.symlink?(entry.backup)
    rescue StandardError => error
      warn "error: rollback failed for #{target}: #{error.message}"
    end
  end

  def backup_path(target)
    File.join(File.dirname(target), ".#{File.basename(target)}.backup-#{Process.pid}-#{SecureRandom.hex(6)}")
  end

  def remove_path(path)
    return unless File.exist?(path) || File.symlink?(path)

    FileUtils.remove_entry(path)
  end
end
