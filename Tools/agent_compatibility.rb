# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "agent_files"
require_relative "agent_skill"
require_relative "file_transaction"

# Claude reads AGENTS.md directly; its skill discovery uses links to canonical folders.
class AgentCompatibility
  attr_reader :legacy_documents, :manual_documents

  def initialize(root)
    @root = File.expand_path(root)
    @source = File.join(@root, ".agents", "skills")
    @target = File.join(@root, ".claude", "skills")
  end

  def preflight!
    %w[.agents .agents/skills .claude .claude/skills].each do |relative|
      path = File.join(@root, relative)
      raise AgentSkill::Error, "#{relative}: expected a directory, not a symlink or file" if
        File.symlink?(path) || (File.exist?(path) && !File.directory?(path))
    end
    names = skill_names
    entries(@target).each do |name|
      path = File.join(@target, name)
      valid = if name == ".gitignore"
        regular_file?(path) && regular_file?(File.join(@source, name)) && FileUtils.compare_file(path, File.join(@source, name))
      elsif File.symlink?(path)
        # A removed canonical skill leaves a recognizable dangling link.
        File.readlink(path) == link_target(name)
      else
        names.include?(name) && same_tree?(File.join(@source, name), path)
      end
      raise AgentSkill::Error, ".claude/skills/#{name}: unrecognized or changed local content; preserved. Reconcile it with .agents/skills/ before running ./sync-agents" unless valid
    end
    documents = AgentFiles.named(@root, "CLAUDE.md")
    @legacy_documents, @manual_documents = documents.partition do |path|
      !relative(path).split("/").include?(".claude") && regular_file?(path) &&
        File.open(path, "rb") { |file| file.gets&.chomp == AgentFiles::MARKER.b }
    end
    @manual_documents += AgentFiles.named(@root, "CLAUDE.local.md", exclude: [".claude"])
    self
  end

  def skill_names
    entries(@source).select do |name|
      path = File.join(@source, name)
      raise AgentSkill::Error, "#{path}: canonical skill must not be a symlink" if File.symlink?(path)
      File.directory?(path)
    end
  end

  def missing_links
    skill_names.count { |name| !File.exist?(File.join(@target, name)) && !File.symlink?(File.join(@target, name)) }
  end

  def copies
    entries(@target).reject { |name| File.symlink?(File.join(@target, name)) }
  end

  def stale_links
    entries(@target) - skill_names
  end

  def warnings
    manual_documents.map do |path|
      "#{relative(path)}: preserved local Claude instructions; these can suppress native AGENTS.md loading. See .agents/references/agent-maintenance.md"
    end
  end

  def validate_source!
    AgentSkill.validate_tree!(@source) if File.directory?(@source)
  end

  def sync
    # Migrate approved copies first so a later partial install can be retried.
    preflight!
    apply if !copies.empty?
    yield if block_given?
    validate_source!
    apply
    warnings.each { |message| warn "warning: #{message}" }
  end

  private

  def apply
    names = skill_names
    replace_links = entries(@target) != names || !copies.empty?
    transaction = FileTransaction.new
    legacy_documents.each { |path| transaction.remove(target: path) }
    if replace_links
      FileUtils.mkdir_p(File.dirname(@target))
      Dir.mktmpdir(".skill-links-", File.dirname(@target)) do |temporary|
        candidate = File.join(temporary, "skills")
        Dir.mkdir(candidate)
        names.each { |name| File.symlink(link_target(name), File.join(candidate, name)) }
        transaction.replace(target: @target, staged: candidate)
        transaction.commit
      end
    else
      transaction.commit
    end
    legacy_documents.each { |path| puts "Removed generated #{relative(path)}" }
    legacy_documents.clear
    puts "Linked .claude/skills/ → .agents/skills/" if replace_links
  end

  def entries(directory)
    File.directory?(directory) ? Dir.children(directory).sort : []
  end

  def regular_file?(path)
    !File.symlink?(path) && File.file?(path)
  end

  def link_target(name)
    "../../.agents/skills/#{name}"
  end

  def same_tree?(source, copy)
    return false unless File.directory?(copy)
    AgentSkill.validate_tree!(source)
    AgentSkill.validate_tree!(copy)
    source_entries = AgentSkill.each_entry(source).map { |path| path.delete_prefix(source) }
    copy_entries = AgentSkill.each_entry(copy).map { |path| path.delete_prefix(copy) }
    source_entries == copy_entries && source_entries.all? do |path|
      a, b = source + path, copy + path
      File.stat(a).mode == File.stat(b).mode &&
        (File.directory?(a) ? File.directory?(b) : regular_file?(b) && FileUtils.compare_file(a, b))
    end
  end

  def relative(path)
    path.delete_prefix("#{@root}/")
  end
end
