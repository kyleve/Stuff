# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../repository'

class RepositoryTest < Minitest::Test
  def test_checkout_depth_worktrees_and_symlinks
    Dir.mktmpdir('repository ü ') do |temporary|
      root = File.realpath(temporary)
      Dir.mkdir(File.join(root, '.git'))
      [0, 1, 5].each do |depth|
        source = File.join(root, *(['nested'] * depth), 'tool.rb')
        FileUtils.mkdir_p(File.dirname(source))
        File.write(source, '')
        assert_equal root, Repository.root(source)
      end
      worktree = File.join(root, 'linked checkout')
      Dir.mkdir(worktree)
      File.write(File.join(worktree, '.git'), 'gitdir: elsewhere')
      source = File.join(worktree, 'tool.rb')
      File.write(source, '')
      link = File.join(root, 'link.rb')
      File.symlink(source, link)
      assert_equal worktree, Repository.root(source)
      assert_equal worktree, Repository.root(link)
    end
  end

  def test_missing_checkout_fails_with_source_path
    Dir.mktmpdir do |root|
      source = File.join(root, 'tool.rb')
      File.write(source, '')
      error = assert_raises(ArgumentError) { Repository.root(source) }
      assert_includes error.message, source
    end
  end
end
