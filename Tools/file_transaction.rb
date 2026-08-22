# frozen_string_literal: true

require "fileutils"
require "securerandom"

# Atomically replaces or removes several filesystem entries with rollback.
class FileTransaction
  class Error < StandardError; end
  class CleanupError < Error; end
  class RollbackError < Error; end

  Operation = Struct.new(:target, :staged, keyword_init: true)
  AppliedOperation = Struct.new(:operation, :backup, :had_original, :installed, keyword_init: true)

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
        had_original = File.exist?(operation.target) || File.symlink?(operation.target)
        File.rename(operation.target, backup) if had_original
        entry = AppliedOperation.new(operation: operation, backup: backup, had_original: had_original, installed: false)
        applied << entry
        if operation.staged
          File.rename(operation.staged, operation.target)
          entry.installed = true
        end
        after_apply(index)
      end
    rescue StandardError => error
      rollback_failures = rollback(applied)
      raise if rollback_failures.empty?

      raise RollbackError,
            "transaction failed (#{error.message}) and rollback failed: #{rollback_failures.join('; ')}"
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
    raise Error, "transaction contains duplicate targets" unless targets.uniq.length == targets.length

    @operations.each do |operation|
      parent = File.dirname(operation.target)
      raise Error, "transaction target parent does not exist: #{operation.target}" unless Dir.exist?(parent)
      raise Error, "transaction target parent is a symlink: #{parent}" if File.symlink?(parent)
      raise Error, "transaction target is a symlink: #{operation.target}" if File.symlink?(operation.target)
      next unless operation.staged

      raise Error, "staged replacement does not exist: #{operation.staged}" unless File.exist?(operation.staged)
      raise Error, "staged replacement is a symlink: #{operation.staged}" if File.symlink?(operation.staged)
      raise Error, "staged replacement must differ from its target: #{operation.target}" if operation.staged == operation.target
      target_device = File.stat(parent).dev
      staged_device = File.stat(File.dirname(operation.staged)).dev
      raise Error, "staged replacement is not on the target filesystem: #{operation.target}" unless target_device == staged_device
    end
  end

  def rollback(applied)
    applied.reverse_each.filter_map do |entry|
      target = entry.operation.target
      unless entry.had_original
        remove_path(target) if entry.installed && (File.exist?(target) || File.symlink?(target))
        next
      end

      replacement = entry.installed ? temporary_path(target, label: "rollback") : nil
      File.rename(target, replacement) if replacement && (File.exist?(target) || File.symlink?(target))
      begin
        File.rename(entry.backup, target)
      rescue StandardError
        File.rename(replacement, target) if replacement && (File.exist?(replacement) || File.symlink?(replacement))
        raise
      end
      remove_path(replacement) if replacement
      nil
    rescue StandardError => error
      "#{target}: #{error.message}"
    end
  end

  def backup_path(target)
    temporary_path(target, label: "backup")
  end

  def temporary_path(target, label:)
    File.join(File.dirname(target), ".#{File.basename(target)}.#{label}-#{Process.pid}-#{SecureRandom.hex(6)}")
  end

  def remove_path(path)
    return unless File.exist?(path) || File.symlink?(path)

    FileUtils.remove_entry(path)
  end
end
