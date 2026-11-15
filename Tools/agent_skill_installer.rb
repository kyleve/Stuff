# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "agent_skill"
require_relative "file_transaction"

# Stages one selected skill on the destination filesystem before replacement.
class AgentSkillInstaller
  ManifestUpdate = Struct.new(:path, :content, keyword_init: true)

  def install(skill, checkout:, destination:, manifest_update: nil)
    source = File.join(checkout, skill.path)
    # Check every path component, including ancestors of the selected directory.
    current = checkout
    skill.path.split("/").each do |component|
      current = File.join(current, component)
      raise AgentSkill::Error, "skill source traverses a symlink: #{current}" if File.symlink?(current)
    end
    AgentSkill.each_entry(source, exclusions: skill.exclusions) { |_entry| }
    parent = File.dirname(destination)
    FileUtils.mkdir_p(parent)
    raise AgentSkill::Error, "skill destination parent is a symlink: #{parent}" if File.symlink?(parent)

    Dir.mktmpdir(".skill-stage-", parent) do |stage|
      payload = File.join(stage, skill.name)
      copy(source, payload, exclusions: skill.exclusions)
      skill.validate_installation!(payload)
      transaction = make_transaction
      transaction.replace(target: destination, staged: payload)
      if manifest_update
        staged_manifest = File.join(stage, "external-skills.json")
        File.write(staged_manifest, manifest_update.content)
        transaction.replace(target: manifest_update.path, staged: staged_manifest)
      end
      transaction.commit
    end
  end

  protected

  def copy(source, destination, exclusions:)
    AgentSkill.each_entry(source, exclusions: exclusions) do |entry|
      target = entry == source ? destination : File.join(destination, entry.delete_prefix("#{source}/"))
      if File.directory?(entry)
        FileUtils.mkdir_p(target)
      else
        FileUtils.cp(entry, target, preserve: true)
      end
    end
  end

  def make_transaction
    FileTransaction.new
  end
end
