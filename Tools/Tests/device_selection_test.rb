# frozen_string_literal: true

require "json"
require "minitest/autorun"

require File.expand_path("../device_selection", __dir__)

class DeviceSelectionTest < Minitest::Test
  def test_selects_an_exact_name_udid_or_identifier
    json = inventory(
      device(identifier: "id-one", udid: "udid-one", name: "Kai's iPhone"),
      device(identifier: "id-two", udid: "udid-two", name: "Work Phone"),
    )

    assert_equal "id-one", DeviceSelection.select(json: json, filter: "KAI'S IPHONE").identifier
    assert_equal "id-one", DeviceSelection.select(json: json, filter: "UDID-ONE").identifier
    assert_equal "id-two", DeviceSelection.select(json: json, filter: "ID-TWO").identifier
  end

  def test_ignores_simulators_and_non_ios_devices
    json = inventory(
      device(identifier: "sim", udid: "sim", name: "Simulator", reality: "simulated"),
      device(identifier: "watch", udid: "watch", name: "Watch", platform: "watchOS"),
      device(identifier: "phone", udid: "phone", name: "Phone"),
    )

    assert_equal "phone", DeviceSelection.select(json: json, filter: "").identifier
  end

  def test_refuses_ambiguity_and_lists_exact_candidates
    json = inventory(
      device(identifier: "one", udid: "one", name: "First"),
      device(identifier: "two", udid: "two", name: "Second"),
    )

    error = assert_raises(DeviceSelection::Error) { DeviceSelection.select(json: json, filter: "") }

    assert_includes error.message, "multiple physical iOS devices"
    assert_includes error.message, "First (one)"
    assert_includes error.message, "Second (two)"
  end

  def test_rejects_missing_identity_and_malformed_shapes
    missing = inventory(device(identifier: nil, udid: nil, name: "Nameless"))
    error = assert_raises(DeviceSelection::Error) { DeviceSelection.select(json: missing, filter: "") }
    assert_includes error.message, "no physical iOS device"

    error = assert_raises(DeviceSelection::Error) do
      DeviceSelection.select(json: JSON.generate("result" => { "devices" => {} }), filter: "")
    end
    assert_includes error.message, "no devices array"

    null_properties = JSON.generate(
      "result" => {
        "devices" => [{
          "identifier" => "bad",
          "properties" => {
            "hardware" => { "platform" => nil, "reality" => nil },
          },
        }],
      },
    )
    error = assert_raises(DeviceSelection::Error) do
      DeviceSelection.select(json: null_properties, filter: "")
    end
    assert_includes error.message, "no physical iOS device"
  end

  private

  def inventory(*devices)
    JSON.generate("result" => { "devices" => devices })
  end

  def device(identifier:, udid:, name:, platform: "iOS", reality: "physical")
    {
      "identifier" => identifier,
      "properties" => {
        "hardware" => { "platform" => platform, "reality" => reality, "udid" => udid },
        "connection" => { "state" => "connected" },
        "state" => { "name" => name },
      },
    }
  end
end
