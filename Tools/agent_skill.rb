# frozen_string_literal: true

require "find"
require "pathname"
require "yaml"

# One pinned upstream skill and its explicitly excluded packaging paths.
class AgentSkill
  class Error < StandardError; end

  attr_reader :name, :repository, :path, :revision, :exclusions

  def initialize(name, entry)
    raise Error, "invalid skill name: #{name.inspect}" unless name.is_a?(String) && name.match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
    raise Error, "#{name}: manifest entry must be an object" unless entry.is_a?(Hash)

    @name = name
    @repository = entry["repo"]
    @path = entry["path"]
    @revision = entry["ref"]
    @exclusions = entry.fetch("exclude", [])
    unless @repository.is_a?(String) && @repository.match?(%r{\A[\w.-]+/[\w.-]+\z})
      raise Error, "#{name}: repo must be owner/repository"
    end
    self.class.validate_relative_path!(@path)
    unless @revision.is_a?(String) && !@revision.empty? && !@revision.start_with?("-")
      raise Error, "#{name}: ref must be a nonempty revision"
    end
    raise Error, "#{name}: exclude must be an array" unless @exclusions.is_a?(Array)
    @exclusions.each do |excluded|
      self.class.validate_relative_path!(excluded)
      raise Error, "#{name}: cannot exclude SKILL.md" if excluded == "SKILL.md"
    end
  end

  def self.validate_relative_path!(path)
    unless path.is_a?(String) && !path.empty? && !path.include?("\0") && !path.include?("\\") &&
        !Pathname.new(path).absolute? && path.split("/", -1).none? { |part| ["", ".", ".."].include?(part) }
      raise Error, "invalid relative skill path: #{path.inspect}"
    end
  end

  def self.metadata(file)
    text = File.read(file, encoding: "UTF-8")
    raise Error, "#{file}: invalid UTF-8" unless text.valid_encoding?
    match = text.match(/\A---\r?\n(.*?)\r?\n---(?:\r?\n|\z)/m)
    raise Error, "#{file}: missing YAML frontmatter" unless match

    metadata = YAML.safe_load(match[1], permitted_classes: [], permitted_symbols: [], aliases: false)
    unless metadata.is_a?(Hash) && %w[name description].all? { |key| metadata[key].is_a?(String) && !metadata[key].strip.empty? }
      raise Error, "#{file}: frontmatter requires nonempty name and description"
    end
    unless metadata["name"].match?(/\A[a-z0-9][a-z0-9-]{0,63}\z/)
      raise Error, "#{file}: invalid skill name #{metadata['name'].inspect}"
    end
    metadata
  rescue Psych::Exception => error
    raise Error, "#{file}: invalid frontmatter: #{error.message}"
  end

  # Excluded packaging is never traversed or copied, including its symlinks.
  def self.each_entry(directory, exclusions: [])
    return enum_for(__method__, directory, exclusions: exclusions) unless block_given?

    raise Error, "missing skill directory: #{directory}" unless File.directory?(directory)
    Find.find(directory) do |entry|
      relative = entry.delete_prefix("#{directory}/")
      Find.prune if exclusions.include?(relative)
      raise Error, "skill package contains a symlink: #{entry}" if File.symlink?(entry)
      raise Error, "skill package contains a special file: #{entry}" unless File.file?(entry) || File.directory?(entry)
      yield entry
    end
  end

  def self.validate_tree!(directory)
    each_entry(directory) { |_entry| }
  end

  def validate_installation!(directory)
    self.class.validate_tree!(directory)
    entries = Dir.glob(File.join(directory, "**", "SKILL.md"), File::FNM_DOTMATCH)
    expected = File.join(directory, "SKILL.md")
    raise Error, "#{name}: expected exactly one root SKILL.md; found #{entries.length}" unless entries == [expected]
    actual = self.class.metadata(expected)["name"]
    raise Error, "#{name}: root SKILL.md declares #{actual.inspect}" unless actual == name
    exclusions.each do |excluded|
      raise Error, "#{name}: excluded packaging remains: #{excluded}" if File.exist?(File.join(directory, excluded))
    end
  end

  def installed?(directory)
    return false unless File.exist?(directory) || File.symlink?(directory)

    validate_installation!(directory)
    true
  rescue Error
    false
  end
end
