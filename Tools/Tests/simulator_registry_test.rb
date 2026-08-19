# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../simulator_registry", __dir__)

class SimulatorRegistryTest < Minitest::Test
  RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
  NAME = "Stuff-checkout-deadbeef-iPhone-17-27.0"

  def test_claims_one_unregistered_device_and_refuses_ambiguity
    with_registry do |registry|
      one = inventory(RUNTIME => [device("one", NAME)])
      result = registry.resolve(**identity, all: one, available: one)
      assert_equal "claim", result.action
      assert_equal "one", result.udid

      twins = inventory(RUNTIME => [device("one", NAME), device("two", NAME)])
      error = assert_raises(RuntimeError) do
        registry.resolve(**identity, all: twins, available: twins)
      end
      assert_includes error.message, "refusing to choose"
    end
  end

  def test_registered_udid_disambiguates_twins
    with_registry do |registry|
      registry.record(name: NAME, checkout: "/repo", udid: "two", device: "iPhone 17", os: "27.0")
      twins = inventory(RUNTIME => [device("one", NAME), device("two", NAME)])

      result = registry.resolve(**identity, all: twins, available: twins)

      assert_equal "owned", result.action
      assert_equal "two", result.udid
    end
  end

  def test_delete_requires_an_exact_registry_claim
    with_registry do |registry|
      exact = inventory(
        RUNTIME => [device("owned", NAME)],
        "com.apple.CoreSimulator.SimRuntime.iOS-26-0" => [device("other", NAME)],
      )
      error = assert_raises(RuntimeError) do
        registry.deletion_target(**identity, all: exact)
      end
      assert_includes error.message, "refusing to delete unowned"

      registry.record(name: NAME, checkout: "/repo", udid: "owned", device: "iPhone 17", os: "27.0")
      result = registry.deletion_target(**identity, all: exact)
      assert_equal "delete", result.action
      assert_equal "owned", result.udid
    end
  end

  def test_rejects_registry_metadata_or_runtime_drift
    with_registry do |registry|
      registry.record(name: NAME, checkout: "/other", udid: "owned", device: "iPhone 17", os: "27.0")
      error = assert_raises(RuntimeError) do
        registry.resolve(**identity, all: inventory, available: inventory)
      end
      assert_includes error.message, "belongs to /other"

      registry.forget(NAME)
      registry.record(name: NAME, checkout: "/repo", udid: "moved", device: "iPhone 17", os: "27.0")
      moved = inventory("another-runtime" => [device("moved", NAME)])
      error = assert_raises(RuntimeError) do
        registry.deletion_target(**identity, all: moved)
      end
      assert_includes error.message, "no longer matches"
    end
  end

  def test_stale_claim_does_not_transfer_to_a_same_named_device
    with_registry do |registry|
      registry.record(name: NAME, checkout: "/repo", udid: "gone", device: "iPhone 17", os: "27.0")
      replacement = inventory(RUNTIME => [device("replacement", NAME)])

      resolve_error = assert_raises(RuntimeError) do
        registry.resolve(**identity, all: replacement, available: replacement)
      end
      assert_includes resolve_error.message, "refusing to replace its claim"

      delete_error = assert_raises(RuntimeError) do
        registry.deletion_target(**identity, all: replacement)
      end
      assert_includes delete_error.message, "matching unowned device"
    end
  end

  def test_record_is_private_atomic_and_require_safe
    Dir.mktmpdir do |directory|
      registry = SimulatorRegistry.new(directory: directory)
      registry.record(name: NAME, checkout: "/repo", udid: "owned", device: "iPhone 17", os: "27.0")

      path = File.join(directory, NAME)
      assert_equal 0o600, File.stat(path).mode & 0o777
      assert_equal [], Dir[File.join(directory, ".*.tmp")]
      assert_equal "owned", registry.load_entry(NAME).udid
    end
  end

  def test_forget_ignores_a_missing_entry_but_surfaces_removal_failures
    Dir.mktmpdir do |directory|
      registry = SimulatorRegistry.new(directory: directory)
      registry.forget(NAME)
      registry.record(name: NAME, checkout: "/repo", udid: "owned", device: "iPhone 17", os: "27.0")
      path = File.join(directory, NAME)

      File.chmod(0o500, directory)
      assert_raises(SystemCallError) { registry.forget(NAME) }
      assert_path_exists path
    ensure
      File.chmod(0o700, directory)
    end
  end

  def test_prune_requires_the_registry_udid_name_and_runtime_to_match
    with_registry do |registry|
      registry.record(name: NAME, checkout: "/gone", udid: "owned", device: "iPhone 17", os: "27.0")
      exact = inventory(RUNTIME => [device("owned", NAME)])
      assert_equal "delete", registry.prune_target(name: NAME, runtime_key: RUNTIME, all: exact).action

      moved = inventory("another-runtime" => [device("owned", NAME)])
      error = assert_raises(RuntimeError) do
        registry.prune_target(name: NAME, runtime_key: RUNTIME, all: moved)
      end
      assert_includes error.message, "refusing to prune"
    end
  end

  private

  def with_registry
    Dir.mktmpdir do |directory|
      yield SimulatorRegistry.new(directory: directory)
    end
  end

  def identity
    {
      name: NAME,
      checkout: "/repo",
      device: "iPhone 17",
      os: "27.0",
      runtime_key: RUNTIME,
    }
  end

  def inventory(devices = {})
    { "devices" => devices }
  end

  def device(udid, name)
    { "udid" => udid, "name" => name, "state" => "Shutdown" }
  end
end
