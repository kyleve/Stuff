# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../InstallerKit/signing_state'

class SigningStateTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('signing state ü')
    @path = File.join(@root, 'installer-signing-job')
    @profiles = File.join(@root, 'Provisioning Profiles')
    @calls = []
    @fail = nil
    security = lambda do |*args|
      @calls << args
      raise 'injected security failure' if args.first == @fail
      if args.first == 'create-keychain'
        File.write(args.last, '')
      elsif args.first == 'delete-keychain'
        File.unlink(args.last)
      end
      '"/original/login keychain-db"'
    end
    @state = InstallerSigning::State.new(@path, @root, @profiles, security)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_cleanup_restores_search_list_and_removes_owned_profiles
    @state.prepare('test-only-key')
    File.write(File.join(@profiles, '11111111-1111-1111-1111-111111111111.mobileprovision'), 'profile')
    @state.cleanup
    refute File.exist?(@path)
    assert Dir.empty?(@profiles)
    assert_includes @calls, ['list-keychains', '-d', 'user', '-s', '/original/login keychain-db']
    refute @calls.any? { |args| args.first == 'default-keychain' }
  end

  def test_security_failure_never_reports_arguments_or_output
    secret = 'test-only-credential'
    failure = Struct.new(:exitstatus) { def success?; false; end }.new(47)
    Open3.stub(:capture2e, ["invalid argument: #{secret}", failure]) do
      error = assert_raises(RuntimeError) { InstallerSigning.run_security(secret, '-p', secret) }
      assert_equal 'security command failed (exit 47)', error.message
      refute_includes error.message, secret
    end
  end

  def test_failed_search_list_restore_still_cleans_other_material_and_can_retry
    @state.prepare('key')
    @fail = 'list-keychains'
    assert_raises(RuntimeError) { @state.cleanup }
    refute File.exist?(File.join(@path, 'signing.keychain-db'))
    assert Dir.empty?(@profiles)
    assert File.exist?(File.join(@path, 'original-keychains.json'))
    @fail = nil
    @state.cleanup
    refute File.exist?(@path)
  end

  def test_existing_profiles_are_untouched_before_any_security_call
    Dir.mkdir(@profiles)
    path = File.join(@profiles, 'unrelated')
    File.write(path, 'keep')
    assert_raises(RuntimeError) { @state.prepare('key') }
    @state.cleanup
    assert_equal 'keep', File.read(path)
    assert_empty @calls
  end

  def test_partial_setup_and_cleanup_failure_can_retry
    @fail = 'unlock-keychain'
    assert_raises(RuntimeError) { @state.prepare('key') }
    @fail = 'delete-keychain'
    assert_raises(RuntimeError) { @state.cleanup }
    assert File.exist?(@path)
    @fail = nil
    @state.cleanup
    refute File.exist?(@path)
  end

  def test_failed_search_list_read_never_restores_partial_state
    @fail = 'list-keychains'
    assert_raises(RuntimeError) { @state.prepare('key') }
    @fail = nil
    @state.cleanup
    assert_equal [['list-keychains', '-d', 'user']], @calls
  end

  def test_unowned_state_and_competing_profile_directory_are_preserved
    Dir.mkdir(@path)
    assert_raises(RuntimeError) { @state.prepare('key') }
    assert_raises(RuntimeError) { @state.cleanup }
    Dir.rmdir(@path)
    @state.prepare('key')
    File.rename(@profiles, "#{@profiles}.owned")
    Dir.mkdir(@profiles)
    assert_raises(RuntimeError) { @state.cleanup }
    assert File.directory?(@path)
    FileUtils.remove_entry(@profiles)
    File.rename("#{@profiles}.owned", @profiles)
    @state.cleanup
  end

  def test_second_job_cannot_claim_the_first_jobs_directory
    @state.prepare('key')
    other = InstallerSigning::State.new(File.join(@root, 'installer-signing-other'), @root, @profiles, ->(*) { raise 'must not call security' })
    assert_raises(RuntimeError) { other.prepare('other key') }
    other.cleanup
    assert File.exist?(File.join(@profiles, InstallerSigning::State::MARKER))
    @state.cleanup
  end

  def test_unexpected_file_is_not_removed
    @state.prepare('key')
    path = File.join(@profiles, 'other-process-file')
    File.write(path, 'keep')
    assert_raises(RuntimeError) { @state.cleanup }
    assert_equal 'keep', File.read(path)
    File.unlink(path)
    @state.cleanup
  end
end
