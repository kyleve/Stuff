# frozen_string_literal: true

require "minitest/autorun"
require "yaml"
require "tempfile"
require "open3"

class TestImpactConfigTest < Minitest::Test
  CONFIG = File.expand_path("../../.circleci/config.yml", __dir__)

  def test_experiment_is_opt_in_and_uses_distinct_check_names
    config = YAML.load_file(CONFIG)
    assert_equal "off", config.fetch("parameters").fetch("test_impact_mode").fetch("default")
    workflows = config.fetch("workflows")
    assert_includes workflows.fetch("iOS CI").fetch("when"), 'pipeline.parameters.test_impact_mode == "off"'
    experiment = workflows.fetch("Test Selection Experiment")
    assert_equal 'pipeline.parameters.test_impact_mode != "off"', experiment.fetch("when")
    assert experiment.fetch("jobs").all? { |job| job.values.first.fetch("name").start_with?("Experiment ") }
  end

  def test_embedded_shell_commands_parse
    walk = lambda do |value|
      case value
      when Hash
        if value["run"].is_a?(Hash) && value["run"]["command"]
          command = value["run"]["command"].gsub(/<<[^>]+>>/, "placeholder")
          Tempfile.create(["circle-command", ".sh"]) do |file|
            file.write(command)
            file.flush
            _, errors, status = Open3.capture3("/bin/bash", "-n", file.path)
            assert status.success?, "#{value["run"]["name"]}: #{errors}"
          end
        end
        value.each_value { |child| walk.call(child) }
      when Array
        value.each { |child| walk.call(child) }
      end
    end
    walk.call(YAML.load_file(CONFIG))
  end
end
