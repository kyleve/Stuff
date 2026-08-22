# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "pathname"
require "tmpdir"

class TlaCheckCommandTest < Minitest::Test
  REPOSITORY = File.expand_path("../..", __dir__)
  EXPECTED_SHA256 = "936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88"

  def test_interrupted_download_preserves_curl_status_and_removes_partial_file
    with_fixture do |fixture|
      stdout, stderr, status = fixture.run("Example", "FAKE_CURL_STATUS" => "23")

      assert_equal 23, status.exitstatus
      assert_includes stdout, "Downloading TLC"
      assert_empty stderr
      refute_path_exists fixture.jar
      assert_empty Dir["#{fixture.jar}.download.*"]
      assert_empty fixture.python_calls
    end
  end

  def test_download_and_cached_checksum_failures_never_publish_or_run_a_bad_jar
    with_fixture do |fixture|
      _stdout, stderr, status = fixture.run("Example", "FAKE_SHA256" => "bad")

      assert_equal 1, status.exitstatus
      assert_includes stderr, "TLC download checksum did not match"
      refute_path_exists fixture.jar
      assert_empty Dir["#{fixture.jar}.download.*"]
      assert_empty fixture.python_calls

      FileUtils.mkdir_p(File.dirname(fixture.jar))
      File.write(fixture.jar, "cached but corrupt")
      _stdout, stderr, status = fixture.run("Example", "FAKE_SHA256" => "bad")

      assert_equal 1, status.exitstatus
      assert_includes stderr, "Cached TLC checksum did not match"
      assert_equal "cached but corrupt", File.read(fixture.jar)
      assert_empty fixture.python_calls
    end
  end

  def test_concurrent_first_downloads_atomically_publish_one_valid_cache_entry
    with_fixture do |fixture|
      environment = fixture.environment("FAKE_CURL_DELAY" => "0.2")
      outputs = 2.times.map { |index| [fixture.root / "out-#{index}", fixture.root / "err-#{index}"] }
      pids = outputs.map do |stdout, stderr|
        Process.spawn(
          environment,
          fixture.command,
          "Example",
          chdir: fixture.outside,
          out: stdout.to_s,
          err: stderr.to_s,
          unsetenv_others: true,
        )
      end
      statuses = pids.map { |pid| Process.wait2(pid).last }

      assert statuses.all?(&:success?), outputs.map { |stdout, stderr| File.read(stdout) + File.read(stderr) }.join
      assert_equal "complete jar", File.read(fixture.jar)
      assert_empty Dir["#{fixture.jar}.download.*"]
      assert_equal 2, fixture.python_calls.length
    end
  end

  private

  Fixture = Struct.new(:root, :command, :outside, :jar, :log, :bin, keyword_init: true) do
    def environment(overrides = {})
      {
        "HOME" => (root / "home").to_s,
        "LC_ALL" => "C",
        "PATH" => "#{bin}:/usr/bin:/bin",
        "TMPDIR" => (root / "temporary files").to_s,
        "TOOL_LOG" => log.to_s,
        "FAKE_SHA256" => TlaCheckCommandTest::EXPECTED_SHA256,
        "FAKE_CURL_STATUS" => "0",
      }.merge(overrides)
    end

    def run(*arguments)
      overrides = arguments.last.is_a?(Hash) ? arguments.pop : {}
      Open3.capture3(
        environment(overrides),
        command,
        *arguments,
        chdir: outside,
        unsetenv_others: true,
      )
    end

    def python_calls
      return [] unless log.exist?
      log.readlines(chomp: true).grep(/^python /)
    end
  end

  def with_fixture
    Dir.mktmpdir("stuff-tla-ü-") do |temporary|
      root = Pathname(temporary) / "repository with spaces"
      bin = root / "fake bin"
      outside = root / "outside cwd"
      FileUtils.mkdir_p([bin, outside, root / "home", root / "temporary files"])
      FileUtils.cp(File.join(REPOSITORY, "tla-check"), root / "tla-check")
      FileUtils.chmod(0o755, root / "tla-check")
      FileUtils.mkdir_p(root / "Tools")
      FileUtils.cp(File.join(REPOSITORY, "Tools", "tla_check.py"), root / "Tools" / "tla_check.py")
      write_spec(root)
      log = root / "commands.log"
      write_fake_tools(bin)

      fixture = Fixture.new(
        root: root,
        command: (root / "tla-check").to_s,
        outside: outside.to_s,
        jar: root / ".build" / "tla" / "v1.7.4" / "tla2tools.jar",
        log: log,
        bin: bin,
      )
      yield fixture
    end
  end

  def write_spec(root)
    spec = root / "Where" / "Specifications" / "Example"
    FileUtils.mkdir_p(spec)
    File.write(spec / "Example.tla", "---- MODULE Example ----\n")
    File.write(spec / "Current.cfg", "SPECIFICATION Spec\n")
    File.write(
      spec / "manifest.json",
      JSON.generate(
        "source" => "tla",
        "module" => "Example.tla",
        "cases" => [{ "name" => "current", "config" => "Current.cfg", "expect" => "pass" }],
      ),
    )
  end

  def write_fake_tools(bin)
    write_executable(bin / "curl", <<~'BASH')
      #!/bin/bash
      output=""
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--output" ]; then
          shift
          output="$1"
        fi
        shift
      done
      printf 'curl %s\n' "$output" >>"$TOOL_LOG"
      printf 'complete jar' >"$output"
      /bin/sleep "${FAKE_CURL_DELAY:-0}"
      exit "${FAKE_CURL_STATUS:-0}"
    BASH
    write_executable(bin / "shasum", <<~'BASH')
      #!/bin/bash
      printf '%s  %s\n' "$FAKE_SHA256" "${3:-}"
    BASH
    write_executable(bin / "python3", <<~'BASH')
      #!/bin/bash
      printf 'python %s\n' "$*" >>"$TOOL_LOG"
      exit 0
    BASH
  end

  def write_executable(path, contents)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
  end
end
