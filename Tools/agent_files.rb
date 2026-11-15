# frozen_string_literal: true

require "find"
require "open3"

# Repository inputs come from Git; generated mirrors need a separate local walk.
module AgentFiles
  EXCLUDED_DIRECTORIES = %w[.git .build Derived .cursor node_modules vendor].freeze
  MARKER = "<!-- Generated from AGENTS.md — do not edit directly -->"

  def self.inventory(root)
    output, error, status = Open3.capture3("git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    raise IOError, "cannot inventory guidance: #{error.strip}" unless status.success?
    output.split("\0").uniq.sort.select { |path| File.exist?(File.join(root, path)) || File.symlink?(File.join(root, path)) }
  end

  def self.named(root, name, exclude: [])
    paths = []
    Find.find(root) do |path|
      if File.directory?(path)
        Find.prune if path != root && (EXCLUDED_DIRECTORIES + exclude).include?(File.basename(path))
      elsif File.basename(path) == name
        paths << path
      end
    end
    paths.sort
  end
end
