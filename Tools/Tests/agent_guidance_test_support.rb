# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module AgentGuidanceTestSupport
  def with_guidance_repository
    Dir.mktmpdir("guidance ü ") do |root|
      _, error, status = Open3.capture3("git", "init", "-q", root)
      raise error unless status.success?
      write_guidance(root, ".gitignore", "CLAUDE.md\n.claude/\nnode_modules/\n")
      write_guidance(root, "AGENTS.md", "# Root\n")
      yield root
    end
  end

  def write_guidance(root, path, content)
    absolute = File.join(root, path)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.binwrite(absolute, content)
    absolute
  end

  def skill_text(name = "example", body: "# Example\n")
    "---\nname: #{name}\ndescription: Use for a concrete task.\n---\n#{body}"
  end

  def validate_guidance(root)
    checker = AgentGuidance.new(root)
    checker.check
    checker
  end
end
