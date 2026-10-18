# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'open3'
require 'shellwords'
require 'securerandom'

module InstallerSigning
  # Owns temporary CI material on an isolated macOS runner. Never used locally.
  class State
    MARKER = 'owned-by-installer-signing'

    def initialize(path, runner_root, profile_root, security)
      @path = File.expand_path(path)
      root = File.expand_path(runner_root)
      raise 'Signing directory must be a direct child of RUNNER_TEMP' unless File.dirname(@path) == root && File.basename(@path).start_with?('where-signing-')
      @profiles = profile_root
      @security = security
    end

    def prepare(private_key)
      raise 'Signing repository deploy key is missing' if private_key.to_s.empty?
      raise 'Signing directory already exists' if File.exist?(@path) || File.symlink?(@path)
      raise 'CI requires an empty, non-symlink provisioning profile directory' if File.symlink?(@profiles) || (File.exist?(@profiles) && (!File.directory?(@profiles) || !Dir.empty?(@profiles)))
      FileUtils.mkdir_p(File.dirname(@path))
      Dir.mkdir(@path, 0o700)
      File.write(File.join(@path, MARKER), '')
      # Save the complete search list before any keychain mutation.
      previous = Shellwords.split(@security.call('list-keychains', '-d', 'user'))
      File.write(File.join(@path, 'original-keychains.json'), JSON.generate(previous))
      FileUtils.mkdir_p(@profiles, mode: 0o700)
      stat = File.stat(@profiles)
      owner = SecureRandom.hex(32)
      File.write(File.join(@path, 'profiles.json'), JSON.generate({ 'inode' => stat.ino, 'device' => stat.dev, 'owner' => owner }))
      File.open(File.join(@profiles, MARKER), File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(owner) }
      password = SecureRandom.hex(32)
      File.write(File.join(@path, 'keychain-password'), password, mode: 'w', perm: 0o600)
      File.write(File.join(@path, 'repository-key'), private_key, mode: 'w', perm: 0o600)
      @security.call('create-keychain', '-p', password, keychain)
      @security.call('set-keychain-settings', '-lut', '7200', keychain)
      @security.call('unlock-keychain', '-p', password, keychain)
      @security.call('list-keychains', '-d', 'user', '-s', keychain, *previous)
    end

    def cleanup
      return unless File.exist?(@path) || File.symlink?(@path)
      raise 'Refusing to clean an unowned signing directory' if File.symlink?(@path) || !File.file?(File.join(@path, MARKER))
      errors = []
      safely(errors) do
        original = File.join(@path, 'original-keychains.json')
        @security.call('list-keychains', '-d', 'user', '-s', *JSON.parse(File.read(original))) if File.file?(original)
      end
      safely(errors) { @security.call('delete-keychain', keychain) if File.exist?(keychain) }
      safely(errors) { clean_profiles }
      raise "Signing cleanup failed. Recovery files remain in #{@path}: #{errors.join('; ')}" unless errors.empty?
      FileUtils.remove_entry(@path)
    end

    private

    def safely(errors)
      yield
    rescue StandardError => e
      errors << e.message
    end

    def keychain
      File.join(@path, 'signing.keychain-db')
    end

    def clean_profiles
      record = File.join(@path, 'profiles.json')
      return unless File.file?(record)
      ownership = JSON.parse(File.read(record))
      return unless File.exist?(@profiles) || File.symlink?(@profiles)
      stat = File.lstat(@profiles)
      raise 'Provisioning profile directory ownership changed' unless stat.directory? && stat.ino == ownership.fetch('inode') && stat.dev == ownership.fetch('device')
      marker = File.join(@profiles, MARKER)
      raise 'Provisioning profile claim changed' unless File.file?(marker) && !File.symlink?(marker) && File.read(marker) == ownership.fetch('owner')
      paths = (Dir.children(@profiles) - [MARKER]).map { |name| File.join(@profiles, name) }
      # Match's UUID filenames are the only files this isolated job can own.
      raise 'Unexpected file in CI profile directory; inspect recovery state' unless paths.all? { |path| /\A[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}\.mobileprovision\z/.match?(File.basename(path)) && File.file?(path) && !File.symlink?(path) }
      paths.each { |path| File.unlink(path) }
      File.unlink(marker)
      File.unlink(record)
    end
  end

  # Even malformed arguments can make security echo credentials to stderr.
  # Keep raw child output out of errors, including the command name from argv.
  def self.run_security(*arguments)
    output, status = Open3.capture2e('security', *arguments)
    raise "security command failed (exit #{status.exitstatus || 'signal'})" unless status.success?
    output
  end

  def self.state_command(argv, environment)
    raise 'Usage: .github/where-signing.sh prepare|cleanup' unless argv.length == 1 && %w[prepare cleanup].include?(argv.first)
    raise 'Temporary signing is restricted to CircleCI isolated runners' unless environment['CIRCLECI'] == 'true'
    security = method(:run_security)
    profiles = File.expand_path('~/Library/Developer/Xcode/UserData/Provisioning Profiles')
    state = State.new(environment.fetch('WHERE_SIGNING_DIR'), environment.fetch('RUNNER_TEMP'), profiles, security)
    if argv.first == 'prepare'
      raise 'MATCH_PASSWORD is required' if environment.fetch('MATCH_PASSWORD', '').empty?
      state.prepare(environment.fetch('MATCH_DEPLOY_KEY'))
    else
      state.cleanup
    end
    0
  rescue StandardError => e
    warn "error: #{e.message}"
    1
  end
end

exit InstallerSigning.state_command(ARGV, ENV) if $PROGRAM_NAME == __FILE__
