# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"

class PublicCommandContractTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)
  COMMANDS = %w[
    test
    profile
    flaky
    simulator
    icons
    Where/install
    Ledger/install
    tla-check
    ide
    swiftformat
    sf-symbols
    sync-agents
    worktree
    xcstrings
    attribution
    shellcheck
    codex-watchdog
    circleci-artifacts
    snapshot-shards
    loc
  ].freeze

  def test_help_is_dependency_free_from_an_unrelated_unicode_working_directory
    Dir.mktmpdir("stuff-cli-ü-") do |temporary|
      home = File.join(temporary, "home with spaces")
      working_directory = File.join(temporary, "outside repository")
      FileUtils.mkdir_p([home, working_directory])
      before = directory_snapshot(working_directory)

      COMMANDS.each do |command|
        stdout, stderr, status = run_command(
          File.join(REPOSITORY, command),
          "--help",
          home: home,
          working_directory: working_directory,
        )

        assert_predicate status, :success?, "#{command} --help failed: #{stderr}"
        refute_empty stdout, "#{command} --help printed no usage"
        assert_empty stderr, "#{command} --help wrote diagnostics: #{stderr}"
      end

      # Interpreters may populate their own caches under HOME or TMPDIR merely
      # by starting. The command's working directory is the state under test.
      assert_equal before, directory_snapshot(working_directory), "--help changed its working directory"
    end
  end

  def test_foundation_wrappers_reject_usage_errors_before_running_dependencies
    assertions = [
      ["ide", ["--unknown"], "unknown option"],
      ["ide", ["--team-id"], "requires a value"],
      ["sync-agents", ["--unknown"], "unknown option"],
      ["sync-agents", ["--add"], "requires a GitHub URL"],
      ["shellcheck", ["--unknown"], "unknown option"],
    ]

    Dir.mktmpdir("stuff-cli-errors-") do |temporary|
      home = File.join(temporary, "home")
      working_directory = File.join(temporary, "cwd")
      FileUtils.mkdir_p([home, working_directory])

      assertions.each do |command, arguments, diagnostic|
        stdout, stderr, status = run_command(
          File.join(REPOSITORY, command),
          *arguments,
          home: home,
          working_directory: working_directory,
        )

        refute_predicate status, :success?, "#{command} #{arguments.join(' ')} unexpectedly succeeded"
        assert_empty stdout
        assert_includes stderr, diagnostic
      end

      assert_empty Dir.children(home)
      assert_empty Dir.children(working_directory)
    end
  end

  private

  def run_command(command, *arguments, home:, working_directory:)
    environment = {
      "HOME" => home,
      "LC_ALL" => "C",
      "PATH" => "/usr/bin:/bin",
      "TMPDIR" => File.dirname(home),
    }
    Open3.capture3(
      environment,
      command,
      *arguments,
      chdir: working_directory,
      unsetenv_others: true,
    )
  end

  def directory_snapshot(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
      .reject { |path| [".", ".."].include?(File.basename(path)) }
      .sort
      .to_h do |path|
        relative = path.delete_prefix("#{root}/")
        value = File.directory?(path) ? :directory : File.binread(path)
        [relative, value]
      end
  end
end
