# frozen_string_literal: true

require "json"
require "pathname"
require "uri"
require_relative "agent_files"
require_relative "agent_markdown"
require_relative "agent_skill"

# Offline validation of repository instruction discovery and canonical skills.
class AgentGuidance
  ROOT_LIMIT = 8 * 1024
  CHAIN_LIMIT = 28 * 1024
  SKILL_LIMIT = 12 * 1024
  INSTRUCTIONS = %w[AGENTS.md AGENTS.override.md].freeze

  attr_reader :errors, :largest_chain, :instruction_count, :skill_count, :missing_external, :missing_mirrors

  def initialize(root)
    @root = File.expand_path(root)
    @errors = []
    @texts = {}
    @missing_external = []
    @missing_mirrors = 0
    @skill_count = 0
    @largest_chain = 0
  end

  def check
    @paths = AgentFiles.inventory(@root)
    instructions = @paths.select { |path| INSTRUCTIONS.include?(File.basename(path)) && !path.start_with?(".claude/") }
    @instruction_count = instructions.length
    check_instructions(instructions)
    check_skills
    documents = @paths.select do |path|
      path.end_with?(".md") && (instructions.include?(path) || path.include?("/Guidance/") ||
        (path.start_with?(".agents/") && !path.include?("/assets/") && !external_path?(path)))
    end
    documents.each do |path|
      inspect_file(path) do
        check_links(path)
        check_links(path, relative_to: path.sub(/\A\.agents\//, ".claude/")) if path.start_with?(".agents/skills/")
      end
    end
    check_mirrors(instructions)
    errors.empty?
  rescue IOError, SystemCallError, JSON::ParserError, AgentSkill::Error => error
    errors << error.message
    false
  end

  def report(output:, diagnostics:)
    diagnostics.puts(errors.map { |error| "error: #{error}" })
    output.puts "Agent guidance: #{instruction_count || 0} instruction files, #{skill_count} repo-owned skills; largest chain #{largest_chain}/#{CHAIN_LIMIT} bytes."
    output.puts "External skills absent (layout checks skipped): #{missing_external.join(', ')}." unless missing_external.empty?
    output.puts "Generated mirrors absent (allowed): #{missing_mirrors}." if missing_mirrors.positive?
    output.puts(errors.empty? ? "Agent guidance checks passed." : "Agent guidance checks failed (#{errors.length}).")
  end

  private

  def read(path)
    @texts[path] ||= begin
      absolute = File.join(@root, path)
      raise AgentSkill::Error, "#{path}: guidance must be a regular file, not a symlink" if File.symlink?(absolute) || !File.file?(absolute)
      text = File.read(absolute, encoding: "UTF-8")
      raise AgentSkill::Error, "#{path}: invalid UTF-8" unless text.valid_encoding?
      text
    end
  end

  def inspect_file(path)
    yield
  rescue AgentSkill::Error, SystemCallError => error
    errors << "#{path}: #{error.message}"
  end

  def check_instructions(instructions)
    selected = {}
    instructions.group_by { |path| File.dirname(path) }.each do |directory, paths|
      paths.each { |path| inspect_file(path) { read(path) } }
      candidates = paths.sort_by { |path| File.basename(path) == "AGENTS.override.md" ? 0 : 1 }
      chosen = candidates.find { |path| @texts[path] && !@texts[path].strip.empty? }
      selected[directory] = chosen if chosen
      next unless directory == "."
      paths.each do |path|
        errors << "#{path}: root instruction is #{@texts[path].bytesize} bytes (limit #{ROOT_LIMIT})" if @texts[path] && @texts[path].bytesize > ROOT_LIMIT
      end
    end
    errors << "AGENTS.md: missing root contract" unless instructions.include?("AGENTS.md")
    selected.each do |directory, path|
      ancestors = (Pathname.new(directory).ascend.map(&:to_s) + ["."]).uniq
      chain = ancestors.reverse.filter_map { |ancestor| selected[ancestor] }
      bytes = chain.sum { |entry| @texts.fetch(entry).bytesize } + 2 * [chain.length - 1, 0].max
      @largest_chain = [largest_chain, bytes].max
      errors << "#{path}: instruction chain is #{bytes} bytes (limit #{CHAIN_LIMIT}): #{chain.join(' -> ')}" if bytes > CHAIN_LIMIT
    end
  end

  def external_path?(path)
    @external_names.any? { |name| path.start_with?(".agents/skills/#{name}/") }
  end

  def check_skills
    manifest_path = File.join(@root, ".agents", "external-skills.json")
    manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
    raise AgentSkill::Error, "external-skills.json must contain an object" unless manifest.is_a?(Hash)
    external = manifest.map { |name, entry| AgentSkill.new(name, entry) }
    @external_names = manifest.keys
    names = manifest.keys.to_h { |name| [name, ".agents/external-skills.json"] }
    owned = @paths.select do |path|
      path.start_with?(".agents/skills/") && !external_path?(path) &&
        (path.split('/').length > 3 || File.symlink?(File.join(@root, path)))
    end
    owned.group_by { |path| path.split('/')[2] }.each do |directory, paths|
      root = ".agents/skills/#{directory}"
      entry = "#{root}/SKILL.md"
      entries = paths.select { |path| File.basename(path) == "SKILL.md" }
      errors << "#{root}: expected exactly one root SKILL.md; found #{entries.join(', ')}" unless entries == [entry]
      next unless entries.include?(entry)
      @skill_count += 1
      inspect_file(entry) do
        content = read(entry)
        metadata = AgentSkill.metadata(File.join(@root, entry))
        name = metadata.fetch("name")
        errors << "#{entry}: duplicate skill name #{name.inspect} (also #{names[name]})" if names.key?(name)
        names[name] = entry
        errors << "#{entry}: name must match directory #{directory.inspect}" unless name == directory
        errors << "#{entry}: skill entry point is #{content.bytesize} bytes (limit #{SKILL_LIMIT})" if content.bytesize > SKILL_LIMIT
      end
    end
    external.each do |skill|
      directory = File.join(@root, ".agents", "skills", skill.name)
      if File.exist?(directory) || File.symlink?(directory)
        inspect_file(".agents/skills/#{skill.name}") { skill.validate_installation!(directory) }
      else
        missing_external << skill.name
      end
    end
  end

  def check_links(path, relative_to: path)
    AgentMarkdown.new(read(path)).links.each do |link|
      target = link.target
      next if target.match?(%r{\A(?:[a-z][a-z0-9+.-]*:|//)}i)
      location, fragment = target.split("#", 2)
      location ||= ""
      location = URI::DEFAULT_PARSER.unescape(location.split("?", 2).first || "")
      absolute = if location.empty?
        File.join(@root, relative_to)
      elsif location.start_with?("/")
        File.join(@root, location.delete_prefix("/"))
      else
        File.expand_path(location, File.dirname(File.join(@root, relative_to)))
      end
      unless absolute == @root || absolute.start_with?("#{@root}/")
        errors << "#{path}:#{link.line}: local link escapes repository: #{target}"
        next
      end
      # Resolve skill-to-skill links against canonical files even on clean
      # checkouts without mirrors. Other .claude paths must actually exist.
      if relative_to != path && absolute.start_with?(File.join(@root, ".claude", "skills") + "/")
        absolute = absolute.sub(File.join(@root, ".claude", "skills") + "/", File.join(@root, ".agents", "skills") + "/")
      end
      unless File.exist?(absolute)
        errors << "#{path}:#{link.line}: missing local link #{target}#{relative_to == path ? '' : ' in Claude mirror'}"
        next
      end
      next unless fragment && !fragment.empty? && File.extname(absolute).downcase == ".md"
      destination = absolute.delete_prefix("#{@root}/")
      unless AgentMarkdown.new(read(destination)).anchors.include?(URI::DEFAULT_PARSER.unescape(fragment))
        errors << "#{path}:#{link.line}: missing anchor #{target}"
      end
    end
  end

  def check_mirrors(instructions)
    sources = instructions.select { |path| File.basename(path) == "AGENTS.md" }
    expected = sources.to_h { |path| [path.sub(/AGENTS\.md\z/, "CLAUDE.md"), path] }
    expected.each do |mirror, source|
      unless File.exist?(File.join(@root, mirror)) || File.symlink?(File.join(@root, mirror))
        @missing_mirrors += 1
        next
      end
      inspect_file(mirror) do
        errors << "#{mirror}: stale generated mirror; run ./sync-agents" unless read(mirror) == "#{AgentFiles::MARKER}\n\n#{read(source)}"
      end
    end
    AgentFiles.named(@root, "CLAUDE.md", exclude: [".claude"]).each do |absolute|
      path = absolute.delete_prefix("#{@root}/")
      next if expected.key?(path) || external_path?(path)
      inspect_file(path) do
        errors << "#{path}: orphan generated mirror; run ./sync-agents" if read(path).start_with?(AgentFiles::MARKER)
      end
    end
    source = File.join(@root, ".agents", "skills")
    mirror = File.join(@root, ".claude", "skills")
    unless File.exist?(mirror) || File.symlink?(mirror)
      @missing_mirrors += 1 if Dir.exist?(source)
      return
    end
    inspect_file(".claude/skills") do
      AgentSkill.validate_tree!(mirror)
      source_files = Dir.glob(File.join(source, "**", "*"), File::FNM_DOTMATCH).reject { |path| File.directory?(path) }.map { |path| path.delete_prefix("#{source}/") }.sort
      mirrored_files = Dir.glob(File.join(mirror, "**", "*"), File::FNM_DOTMATCH).reject { |path| File.directory?(path) }.map { |path| path.delete_prefix("#{mirror}/") }.sort
      stale = source_files != mirrored_files || source_files.any? { |path| File.binread(File.join(source, path)) != File.binread(File.join(mirror, path)) }
      errors << ".claude/skills: stale skill mirror; run ./sync-agents" if stale
    end
  end
end
