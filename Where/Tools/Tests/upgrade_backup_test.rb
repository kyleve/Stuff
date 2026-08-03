# frozen_string_literal: true

require "minitest/autorun"
require_relative "../upgrade-backup"

class UpgradeBackupTest < Minitest::Test
  DEVICE_ID = "store://devices/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

  def test_v3_final_archive_state_out_ranks_its_later_monotonic_off_cutoff
    manifest = {
      "formatVersion" => 3,
      "samples" => [],
      "evidence" => [],
      "manualDays" => [],
      "dismissedIssues" => [],
      "trackedRegions" => [],
      "primaryRegions" => [],
      "assets" => [],
      "recordingDevices" => [
        {
          "id" => DEVICE_ID,
          "systemName" => "iPad",
          "kind" => "tablet",
          "registeredAt" => 100.0,
          "lastSeenAt" => 200.0,
          "archivedAt" => 200.0,
          "lastAppliedPolicyChangeID" => "22222222-2222-2222-2222-222222222222",
          "status" => "off",
          "nickname" => nil,
        },
      ],
      "recordingPolicyChanges" => [
        {
          "id" => "11111111-1111-1111-1111-111111111111",
          "deviceID" => DEVICE_ID,
          "effectiveAt" => 100.0,
          "isEnabled" => true,
        },
        {
          "id" => "22222222-2222-2222-2222-222222222222",
          "deviceID" => DEVICE_ID,
          # The v3 writer advanced equal/backward cutoffs by one microsecond.
          "effectiveAt" => 200.000001,
          "isEnabled" => false,
        },
      ],
    }

    upgraded = upgrade_manifest(manifest)
    policies = upgraded.fetch("recordingPolicyChanges")

    assert_equal [0, 1, 2], policies.map { |policy| policy.fetch("revision") }
    assert_equal [
      [],
      [policies[0].fetch("id")],
      [policies[1].fetch("id")],
    ], policies.map { |policy| policy.fetch("parentIDs") }
    refute policies.any? { |policy| policy.key?("parentID") }
    assert_equal "archived", policies.last.fetch("state")
    assert_equal "archive", policies.last.fetch("reason")
  end

  def test_v3_active_device_expands_into_current_tables_idempotently
    policy_id = "11111111-1111-1111-1111-111111111111"
    manifest = base_manifest(3).merge(
      "recordingDevices" => [
        {
          "id" => DEVICE_ID,
          "systemName" => "iPhone",
          "kind" => "phone",
          "registeredAt" => 100.0,
          "lastSeenAt" => 200.0,
          "archivedAt" => nil,
          "lastAppliedPolicyChangeID" => policy_id,
          "status" => "recording",
          "nickname" => "Travel phone",
        },
      ],
      "recordingPolicyChanges" => [
        {
          "id" => policy_id,
          "deviceID" => DEVICE_ID,
          "effectiveAt" => 100.0,
          "isEnabled" => true,
        },
      ],
    )

    upgraded = upgrade_manifest(deep_copy(manifest))

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
    refute upgraded.key?("recordingDevices")
    assert_equal [
      {
        "id" => DEVICE_ID,
        "systemName" => "iPhone",
        "kind" => "phone",
        "registeredAt" => 100.0,
        "registrationEpochID" => { "rawValue" => INITIAL_DATA_EPOCH_ID },
      },
    ], upgraded.fetch("recordingDeviceProfiles")

    metadata = upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal 1, metadata.length
    assert_equal DEVICE_ID, metadata.first.fetch("deviceID")
    assert_equal "nickname", metadata.first.fetch("field")
    assert_equal 0, metadata.first.fetch("revision")
    assert_equal 200.0, metadata.first.fetch("changedAt")
    assert_equal DEVICE_ID, metadata.first.fetch("changedByDeviceID")
    assert_equal "Travel phone", metadata.first.fetch("nickname")

    assert_equal [
      {
        "deviceID" => DEVICE_ID,
        "revision" => 0,
        "lastSeenAt" => 200.0,
        "appliedAt" => 200.0,
        "lastAppliedPolicyChangeID" => policy_id,
        "status" => "recording",
      },
    ], upgraded.fetch("recordingDeviceCheckIns")

    policy = upgraded.fetch("recordingPolicyChanges").fetch(0)
    assert_equal policy_id, policy.fetch("id")
    assert_equal DEVICE_ID, policy.fetch("deviceID")
    assert_equal [], policy.fetch("parentIDs")
    refute policy.key?("parentID")
    assert_equal 0, policy.fetch("revision")
    assert_equal 100.0, policy.fetch("issuedAt")
    assert_equal DEVICE_ID, policy.fetch("issuedByDeviceID")
    assert_equal 100.0, policy.fetch("effectiveAt")
    assert_equal "on", policy.fetch("state")
    assert_equal "initialRegistration", policy.fetch("reason")

    assert_equal upgraded, upgrade_manifest(deep_copy(upgraded))
  end

  def test_v4_preserves_independent_tables_and_links_flat_policy_revisions
    root_id = "11111111-1111-1111-1111-111111111111"
    on_id = "22222222-2222-2222-2222-222222222222"
    off_id = "33333333-3333-3333-3333-333333333333"
    descendant_id = "44444444-4444-4444-4444-444444444444"
    profile = {
      "id" => DEVICE_ID,
      "systemName" => "iPad",
      "kind" => "tablet",
      "registeredAt" => 100.0,
    }
    metadata = [
      {
        "id" => "aaaaaaaa-1111-1111-1111-111111111111",
        "deviceID" => DEVICE_ID,
        "field" => "nickname",
        "revision" => 0,
        "changedAt" => 110.0,
        "changedByDeviceID" => DEVICE_ID,
        "nickname" => "Kitchen iPad",
      },
    ]
    check_ins = [
      {
        "deviceID" => DEVICE_ID,
        "revision" => 7,
        "lastSeenAt" => 140.0,
        "appliedAt" => 140.0,
        "lastAppliedPolicyChangeID" => off_id,
        "status" => "off",
      },
    ]
    policies = [
      policy(root_id, revision: 0, state: "off", effective_at: 100.0),
      policy(on_id, revision: 1, state: "on", effective_at: 120.0),
      policy(off_id, revision: 1, state: "off", effective_at: 121.0),
      policy(descendant_id, revision: 2, state: "on", effective_at: 130.0),
    ]
    manifest = base_manifest(4).merge(
      "recordingDeviceProfiles" => [profile],
      "recordingDeviceMetadataChanges" => metadata,
      "recordingDeviceCheckIns" => check_ins,
      "recordingPolicyChanges" => policies,
    )

    upgraded = upgrade_manifest(deep_copy(manifest))
    upgraded_policies = upgraded.fetch("recordingPolicyChanges")

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
    assert_equal [profile.merge(
      "registrationEpochID" => { "rawValue" => INITIAL_DATA_EPOCH_ID },
    )], upgraded.fetch("recordingDeviceProfiles")
    assert_equal metadata, upgraded.fetch("recordingDeviceMetadataChanges")
    assert_equal check_ins, upgraded.fetch("recordingDeviceCheckIns")
    assert_equal policies, upgraded_policies.map { |entry| entry.reject { |key| key == "parentIDs" } }
    assert_equal [], upgraded_policies[0].fetch("parentIDs")
    assert_equal [root_id], upgraded_policies[1].fetch("parentIDs")
    assert_equal [root_id], upgraded_policies[2].fetch("parentIDs")
    # The old flat resolver preferred Off at the concurrent revision, so the
    # formerly ambiguous revision-2 event is attached to that deterministic winner.
    assert_equal [off_id], upgraded_policies[3].fetch("parentIDs")
    refute upgraded_policies.any? { |entry| entry.key?("parentID") }
  end

  def test_v6_converts_nullable_scalar_policy_parents_to_parent_sets
    root_id = "11111111-1111-1111-1111-111111111111"
    child_id = "22222222-2222-2222-2222-222222222222"
    policies = [
      policy(root_id, revision: 0, state: "off", effective_at: 100.0).merge(
        "parentID" => nil,
      ),
      policy(child_id, revision: 1, state: "on", effective_at: 120.0).merge(
        "parentID" => root_id,
      ),
    ]
    manifest = base_manifest(6).merge("recordingPolicyChanges" => policies)

    upgraded = upgrade_manifest(deep_copy(manifest))
    upgraded_policies = upgraded.fetch("recordingPolicyChanges")

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
    assert_equal [[], [root_id]], upgraded_policies.map { |entry| entry.fetch("parentIDs") }
    refute upgraded_policies.any? { |entry| entry.key?("parentID") }
    assert_equal upgraded, upgrade_manifest(deep_copy(upgraded))
  end

  def test_v7_preserves_a_sorted_multi_parent_set
    parent_ids = [
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222",
    ]
    join = policy(
      "33333333-3333-3333-3333-333333333333",
      revision: 2,
      state: "off",
      effective_at: 130.0,
    ).merge("parentIDs" => parent_ids)
    manifest = base_manifest(7).merge("recordingPolicyChanges" => [join])

    upgraded = upgrade_manifest(deep_copy(manifest))

    assert_equal CURRENT_FORMAT_VERSION, upgraded.fetch("formatVersion")
    assert_equal parent_ids, upgraded.fetch("recordingPolicyChanges").fetch(0).fetch("parentIDs")
    refute upgraded.fetch("recordingPolicyChanges").fetch(0).key?("parentID")
  end

  private

  def base_manifest(version)
    {
      "formatVersion" => version,
      "exportedAt" => 0.0,
      "samples" => [],
      "evidence" => [],
      "manualDays" => [],
      "dismissedIssues" => [],
      "trackedRegions" => [],
      "primaryRegions" => [],
      "assets" => [],
    }
  end

  def policy(id, revision:, state:, effective_at:)
    {
      "id" => id,
      "deviceID" => DEVICE_ID,
      "revision" => revision,
      "issuedAt" => effective_at,
      "issuedByDeviceID" => DEVICE_ID,
      "effectiveAt" => effective_at,
      "state" => state,
      "reason" => revision.zero? ? "initialRegistration" : "userCommand",
    }
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value))
  end
end
