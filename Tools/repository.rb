# frozen_string_literal: true

# Locate a tool's checkout independently of directory depth or the working directory.
module Repository
  def self.root(source_file)
    directory = File.dirname(File.realpath(source_file))
    loop do
      marker = File.join(directory, '.git')
      return directory if File.directory?(marker) || File.file?(marker)
      parent = File.dirname(directory)
      raise ArgumentError, "Cannot find a Git checkout containing #{source_file}" if parent == directory
      directory = parent
    end
  end
end
