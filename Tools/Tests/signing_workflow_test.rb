# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'ostruct'
require_relative '../InstallerKit/signing_workflow'

# Fake action boundary: no network, keychain, Apple account, or device access.
class SigningActions
  attr_reader :calls
  attr_accessor :failure, :missing_ipa
  def initialize
    @calls = []
  end
  def match(**options)
    @calls << [:match, options]
    raise 'store unavailable' if failure == :match
  end
  def register_devices(**options)
    @calls << [:register_devices, options]
    raise 'Apple unavailable' if failure == :register_devices
  end
  def build_app(**options)
    @calls << [:build_app, options]
    raise 'export failed' if failure == :build_app
    return if missing_ipa
    FileUtils.mkdir_p(options.fetch(:output_directory))
    File.write(File.join(options.fetch(:output_directory), options.fetch(:output_name)), 'ipa')
  end
end

class SigningWorkflowTest < Minitest::Test
  ROOT = File.expand_path('../..', __dir__)
  def setup
    @root = Dir.mktmpdir('source ü ')
    @env = ENV.to_h
    ENV.delete('CI')
    ENV.delete('CIRCLECI')
    ENV['TUIST_DEVELOPMENT_TEAM'] = 'TESTTEAM01'
    ENV['MATCH_PASSWORD'] = 'test-only-password'
    @key = File.join(@root, 'key.json')
    File.write(@key, JSON.generate({ key_id: 'test-key', issuer_id: 'test-team', key: 'test-only-key' }))
    ENV['INSTALLER_API_KEY_PATH'] = @key
    @output = File.join(@root, 'output')
    @actions = SigningActions.new
    @options = { app: 'where', source: @root, output: @output, name: 'Phone', udid: '00008110-00123456789ABCDE' }
    @workflow = InstallerSigning::Workflow.new(@actions, @options)
    @targets = JSON.parse(File.read(InstallerSigning::Workflow::DESCRIPTORS)).fetch('where').fetch('targets')
    @profiles = @targets.each_with_index.map do |target, index|
      { 'target' => target.fetch('name'), 'bundle_id' => "example.app.target#{index}", 'team' => 'TESTTEAM01',
        'uuid' => "#{(index + 1).to_s * 8}-1111-1111-1111-111111111111" }
    end
    @settings = @profiles.map do |p|
      { 'target' => p.fetch('target'), 'buildSettings' => {
        'PRODUCT_BUNDLE_IDENTIFIER' => p.fetch('bundle_id'), 'DEVELOPMENT_TEAM' => p.fetch('team'),
        'PROVISIONING_PROFILE_SPECIFIER' => p.fetch('uuid'), 'CODE_SIGN_STYLE' => 'Manual', 'WHERE_AUDIENCE' => 'development'
      } }
    end
    @commands = []
    settings = @settings
    commands = @commands
    # Project generation is the subprocess seam. Profile policy still executes for real.
    @workflow.define_singleton_method(:build_settings) { settings }
    @workflow.define_singleton_method(:run) do |*arguments, **keywords|
      commands << arguments
      if arguments.first == 'python3'
        super(*arguments, **keywords)
      end
    end
    @workflow.define_singleton_method(:capture) do |*arguments|
      File.binread(arguments.last)
    end
    @profiles.each_with_index do |profile, index|
      path = File.join(@root, "#{profile.fetch('target')}.plist")
      script = <<~PY
        import plistlib, datetime, sys
        plistlib.dump({'UUID': sys.argv[2], 'TeamIdentifier':['TESTTEAM01'],
          'ApplicationIdentifierPrefix':['TESTTEAM01'], 'ExpirationDate':datetime.datetime(2099,1,1),
          'ProvisionedDevices':['test-device'], 'Entitlements':{'get-task-allow':False,
          'application-identifier':'TESTTEAM01.'+sys.argv[3]}},open(sys.argv[1],'wb'))
      PY
      raise 'fixture failure' unless system('python3', '-c', script, path, profile.fetch('uuid'), profile.fetch('bundle_id'))
      ENV["sigh_#{profile.fetch('bundle_id')}_adhoc_profile-path"] = path
    end
    plan = File.join(@root, 'plan')
    raise 'fixture plan failure' unless system('python3', '-m', 'Tools.InstallerKit.signing_profiles', 'prepare',
      '--profiles', @root, '--output', plan, '--descriptor', InstallerSigning::Workflow::DESCRIPTORS, '--app', 'where', chdir: ROOT)
    @export_options = File.join(plan, 'ExportOptions.plist')
  end

  def teardown
    ENV.replace(@env)
    FileUtils.remove_entry(@root)
  end

  def test_readonly_archive_validates_all_targets_and_preserves_local_metadata
    @workflow.archive
    match = @actions.calls.first.last
    assert_equal true, match.fetch(:readonly)
    assert_equal false, match.fetch(:renew_expired_certs)
    refute match.key?(:api_key_path)
    assert_equal @profiles.map { |p| p.fetch('bundle_id') }, match.fetch(:app_identifier)
    assert File.file?(File.join(@output, 'export/Where.ipa'))
    build = @actions.calls.last.last
    assert_equal 'Debug', build.fetch(:configuration)
    assert_equal 'Where Development', build.fetch(:scheme)
    assert_equal ['SWIFT_OPTIMIZATION_LEVEL=-O', 'GCC_OPTIMIZATION_LEVEL=s', 'INSTALLER_APP_ID=where'], Shellwords.split(build.fetch(:xcargs))
    assert_equal 2, @commands.count { |args| args.last == '--no-open' }
    @targets.each { |target| assert_nil ENV[target.fetch('environment_key')] }
  end

  def test_refresh_renews_expired_certificates_and_all_profiles
    @workflow.refresh
    assert_equal [:match], @actions.calls.map(&:first)
    match = @actions.calls.first.last
    assert_equal false, match.fetch(:readonly)
    assert_equal true, match.fetch(:renew_expired_certs)
    assert_equal true, match.fetch(:force)
    assert_equal @key, match.fetch(:api_key_path)
  end

  def test_ci_archive_keeps_certificate_renewal_disabled
    ENV['CIRCLECI'] = 'true'
    ENV['WHERE_SIGNING_DIR'] = @root
    File.write(File.join(@root, 'owned-by-installer-signing'), '')
    File.write(File.join(@root, 'keychain-password'), 'test-only-password')
    @workflow.archive
    match = @actions.calls.first.last
    assert_equal true, match.fetch(:readonly)
    assert_equal false, match.fetch(:renew_expired_certs)
    refute match.key?(:api_key_path)
  end

  def test_device_registration_precedes_forced_refresh_of_all_profiles
    @workflow.register_device
    assert_equal [:register_devices, :match], @actions.calls.map(&:first)
    match = @actions.calls.last.last
    assert_equal false, match.fetch(:readonly)
    assert_equal true, match.fetch(:force)
    assert_equal true, match.fetch(:renew_expired_certs)
    assert_equal @key, match.fetch(:api_key_path)
    assert_equal 3, match.fetch(:app_identifier).length
  end

  def test_registration_failure_stops_before_match
    @actions.failure = :register_devices
    assert_raises(RuntimeError) { @workflow.register_device }
    assert_equal [:register_devices], @actions.calls.map(&:first)
  end

  def test_match_failure_is_actionable_and_no_archive_is_created
    @actions.failure = :match
    error = assert_raises(RuntimeError) { @workflow.archive }
    assert_includes error.message, './signing refresh --app where'
    refute File.exist?(@output)
  end

  def test_mismatched_resolved_profile_prevents_archive
    @settings[1]['buildSettings']['PROVISIONING_PROFILE_SPECIFIER'] = 'wrong'
    assert_raises(SystemExit) { @workflow.archive }
    assert_equal [:match], @actions.calls.map(&:first)
    refute File.exist?(@output)
  end

  def test_export_failure_restores_environment_and_keeps_output_for_diagnostics
    @actions.failure = :build_app
    assert_raises(RuntimeError) { @workflow.archive }
    assert File.directory?(@output)
    @targets.each { |target| assert_nil ENV[target.fetch('environment_key')] }
    assert_equal [:match, :build_app], @actions.calls.map(&:first)
  end

  def test_missing_ipa_is_failure_and_ci_cannot_maintain_assets
    @actions.missing_ipa = true
    assert_raises(RuntimeError) { @workflow.archive }
    ENV['CIRCLECI'] = 'true'
    assert_raises(RuntimeError) { @workflow.refresh }
  end

  def test_ci_metadata_is_safely_passed_to_xcode
    ENV['INSTALLER_CHANNEL'] = 'pr-42'
    ENV['INSTALLER_FEED_URL'] = 'https://example.com/a?x=one&y=two'
    arguments = Shellwords.split(@workflow.build_options(@output, @export_options).fetch(:xcargs))
    assert_includes arguments, 'INSTALLER_CHANNEL=pr-42'
    assert_includes arguments, 'INSTALLER_FEED_URL=https://example.com/a?x=one&y=two'
  end

  def test_pinned_gym_accepts_options_and_generates_manual_export_plist
    FileUtils.mkdir_p(File.join(@root, 'Stuff.xcworkspace'))
    options = File.join(@root, 'options.json')
    File.write(options, JSON.generate(@workflow.build_options(@output, @export_options)))
    script = <<~RUBY
      require 'json'
      require 'fastlane'
      require 'gym'
      require 'fastlane/actions/build_app'
      require 'fastlane/actions/sync_code_signing'
      options = JSON.parse(File.read(ARGV[0]), symbolize_names: true)
      # Exercise build_app's Match integration too: it must not substitute profile names.
      Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::MATCH_PROVISIONING_PROFILE_MAPPING] =
        { 'example.app.target0' => 'match AdHoc wrong-profile' }
      class Gym::Manager
        def work(values)
          abort 'export plist replaced' unless values[:export_options].is_a?(String)
          nil
        end
      end
      Fastlane::Actions::BuildAppAction.run(options)
      # Keep the real option validators and plist generator. Skip Xcode project discovery.
      configuration = FastlaneCore::Configuration.create(Gym::Options.available_options, options)
      Gym.instance_variable_set(:@config, configuration)
      Gym::DetectValues.ensure_export_options_is_hash
      content = Gym::PackageCommandGeneratorXcode7.send(:config_content)
      parsed = CFPropertyList.native_types(CFPropertyList::List.new(data: content).value)
      abort 'wrong export method' unless parsed['method'] == 'ad-hoc'
      abort 'missing profiles' unless parsed['provisioningProfiles'].length == 3
      abort 'UUID replaced' unless parsed['provisioningProfiles']['example.app.target0'] == '11111111-1111-1111-1111-111111111111'
      abort 'version changed' unless parsed['manageAppVersionAndBuildNumber'] == false
    RUBY
    stdout, status = Open3.capture2e({ 'BUNDLE_GEMFILE' => File.join(ROOT, 'Gemfile'), 'BUNDLE_PATH' => File.join(ROOT, 'vendor/bundle'), 'FASTLANE_SKIP_UPDATE_CHECK' => '1' },
                                  'mise', 'exec', '--', 'bundle', 'exec', 'ruby', '-e', script, options, chdir: ROOT)
    assert status.success?, stdout
  end
end
