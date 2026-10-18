# frozen_string_literal: true

require 'json'
require_relative '../repository'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'shellwords'

module InstallerSigning
  # Trusted orchestration. The selected source supplies project/build scripts only.
  class Workflow
    ROOT = Repository.root(__FILE__)
    DESCRIPTORS = File.join(ROOT, '.github/installer-signing-apps.json')
    STORE = 'git@github.com:kyleve/Stuff-Signing.git'

    def initialize(actions, options)
      @actions = actions
      @app = options.fetch(:app) { options.fetch('app') }
      @source = File.realpath(options.fetch(:source) { options.fetch('source') })
      @options = options
      @descriptor = JSON.parse(File.read(DESCRIPTORS)).fetch(@app)
    end

    def refresh
      maintenance!
      with_project do |identifiers|
        @actions.match(**match_options(identifiers, readonly: false).merge(force: true))
      end
    end

    def register_device
      maintenance!
      with_project do |identifiers|
        @actions.register_devices(devices: { option(:name) => option(:udid) },
                                  api_key_path: ENV.fetch('INSTALLER_API_KEY_PATH'), team_id: team)
        @actions.match(**match_options(identifiers, readonly: false).merge(force: true))
      end
    end

    def archive
      output = File.expand_path(option(:output))
      raise 'Output directory already exists' if File.exist?(output) || File.symlink?(output)
      with_project do |identifiers|
        begin
          @actions.match(**match_options(identifiers, readonly: true))
        rescue StandardError => e
          raise "Could not read signing assets: #{e.message}\nRun ./signing refresh --app #{@app} locally to repair missing or expired assets."
        end
        Dir.mktmpdir('installer-profiles-') do |temporary|
          File.chmod(0o700, temporary)
          @descriptor.fetch('targets').zip(identifiers).each do |target, identifier|
            path = ENV.fetch("sigh_#{identifier}_adhoc_profile-path")
            File.binwrite(File.join(temporary, "#{target.fetch('name')}.plist"),
                          capture('security', 'cms', '-D', '-i', path))
          end
          plan = File.join(temporary, 'plan')
          policy('prepare', '--profiles', temporary, '--output', plan)
          profiles = JSON.parse(File.read(File.join(plan, 'profiles.json')))
          raise 'Profiles do not match the configured team' unless profiles.all? { |profile| profile.fetch('team') == team }
          overrides = @descriptor.fetch('targets').zip(profiles).to_h do |target, profile|
            [target.fetch('environment_key'), profile.fetch('uuid')]
          end
          with_environment(overrides) do
            run(File.join(@source, 'ide'), '--no-open')
            settings_path = File.join(temporary, 'settings.json')
            File.write(settings_path, JSON.generate(build_settings))
            policy('validate-settings', '--settings', settings_path, '--profiles', File.join(plan, 'profiles.json'))
            FileUtils.mkdir_p(output)
            @actions.build_app(**build_options(output, File.join(plan, 'ExportOptions.plist')))
            raise 'Xcode did not export the expected IPA' unless File.file?(File.join(output, 'export', "#{@descriptor.fetch('product')}.ipa"))
          end
        end
      end
    end

    # Public for a real Gym configuration contract test without Xcode or signing.
    def build_options(output, export_options)
      arguments = ['SWIFT_OPTIMIZATION_LEVEL=-O', 'GCC_OPTIMIZATION_LEVEL=s', "INSTALLER_APP_ID=#{@app}"]
      %w[INSTALLER_REPOSITORY_URL INSTALLER_CHANNEL INSTALLER_RUN INSTALLER_ATTEMPT INSTALLER_FEED_URL].each do |key|
        arguments << "#{key}=#{ENV.fetch(key)}" if ENV[key] && !ENV[key].empty?
      end
      {
        workspace: File.join(@source, 'Stuff.xcworkspace'), scheme: @descriptor.fetch('scheme'),
        configuration: @descriptor.fetch('configuration'), destination: 'generic/platform=iOS',
        archive_path: File.join(output, "#{@descriptor.fetch('product')}.xcarchive"),
        derived_data_path: File.join(output, 'DerivedData'), output_directory: File.join(output, 'export'),
        output_name: "#{@descriptor.fetch('product')}.ipa", buildlog_path: File.join(output, 'logs'),
        # Gym 2.241.1 rejects release-testing. Xcode still accepts this alias.
        export_method: 'ad-hoc', skip_profile_detection: true, xcodebuild_formatter: '',
        xcargs: arguments.shelljoin,
        # A plist path prevents build_app from replacing validated UUIDs with Match names.
        export_options: export_options
      }
    end

    private

    def option(key)
      @options.fetch(key) { @options.fetch(key.to_s) }
    end

    def team
      value = ENV.fetch('TUIST_DEVELOPMENT_TEAM') { raise 'Set TUIST_DEVELOPMENT_TEAM with ./ide --team-id TEAM' }
      raise 'Invalid Apple Developer team ID' unless /\A[A-Z0-9]{10}\z/.match?(value)
      value
    end

    def maintenance!
      raise 'Signing maintenance is local only' if ENV['CI'] || ENV['CIRCLECI']
      raise 'Set INSTALLER_API_KEY_PATH to a local Team API-key JSON file' unless File.file?(ENV.fetch('INSTALLER_API_KEY_PATH', ''))
      key = JSON.parse(File.read(ENV.fetch('INSTALLER_API_KEY_PATH')))
      raise 'The Team API-key JSON needs key_id, issuer_id, and key' unless key.is_a?(Hash) && %w[key_id issuer_id key].all? { |field| key[field].is_a?(String) && !key[field].empty? }
    end

    def match_options(identifiers, readonly:)
      options = { type: 'adhoc', platform: 'ios', app_identifier: identifiers, team_id: team,
                  git_url: STORE, git_branch: 'main', readonly: readonly,
                  renew_expired_certs: !readonly, clone_branch_directly: true }
      options[:api_key_path] = ENV.fetch('INSTALLER_API_KEY_PATH') unless readonly
      if ENV['CIRCLECI']
        state = ENV.fetch('WHERE_SIGNING_DIR')
        raise 'Temporary signing state is missing' unless File.file?(File.join(state, 'owned-by-installer-signing'))
        options.merge!(keychain_name: File.join(state, 'signing.keychain-db'),
                       keychain_password: File.read(File.join(state, 'keychain-password')),
                       git_private_key: File.join(state, 'repository-key'))
      end
      options
    end

    def with_project
      team
      raise 'Set MATCH_PASSWORD to the signing repository encryption password' if ENV.fetch('MATCH_PASSWORD', '').empty?
      Dir.chdir(ROOT) do
        # Resolve identities from Project.swift, without stale manual-profile overrides.
        reset = @descriptor.fetch('targets').to_h { |target| [target.fetch('environment_key'), nil] }
        with_environment(reset) do
          run(File.join(@source, 'ide'), '--no-open')
          settings = build_settings
          identifiers = @descriptor.fetch('targets').map do |target|
            matches = settings.select { |item| item['target'] == target.fetch('name') }
            raise "Expected one build-settings entry for #{target.fetch('name')}" unless matches.length == 1
            values = matches.first.fetch('buildSettings')
            @descriptor.fetch('required_settings').merge('DEVELOPMENT_TEAM' => team).each do |key, value|
              raise "#{target.fetch('name')}: unexpected #{key}" unless values[key] == value
            end
            value = values.fetch('PRODUCT_BUNDLE_IDENTIFIER')
            raise 'Expected an explicit bundle identifier' unless /\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/.match?(value)
            value
          end
          raise 'Targets must have distinct bundle identifiers' unless identifiers.uniq == identifiers
          yield identifiers
        end
      end
    end

    def build_settings
      JSON.parse(capture('mise', 'exec', '--', 'xcodebuild', '-showBuildSettings', '-json',
                         '-project', File.join(@source, 'Stuff.xcodeproj'),
                         *@descriptor.fetch('targets').flat_map { |target| ['-target', target.fetch('name')] },
                         '-configuration', @descriptor.fetch('configuration'), '-sdk', 'iphoneos'))
    end

    def policy(*arguments)
      run('python3', '-m', 'Tools.InstallerKit.signing_profiles', *arguments,
          '--descriptor', DESCRIPTORS, '--app', @app, directory: ROOT)
    end

    def capture(*arguments)
      stdout, status = Open3.capture2(*arguments, chdir: @source)
      raise SystemExit, (status.exitstatus || 1) unless status.success?
      stdout
    end

    def run(*arguments, directory: @source)
      return if system(*arguments, chdir: directory)
      raise SystemExit, ($?&.exitstatus || 1)
    end

    def with_environment(values)
      previous = values.to_h { |key, _| [key, ENV[key]] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end
end
