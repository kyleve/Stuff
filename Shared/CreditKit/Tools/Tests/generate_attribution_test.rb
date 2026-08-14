# frozen_string_literal: true

require "minitest/autorun"
require_relative "../generate-attribution"

class GenerateAttributionTest < Minitest::Test
  FIXTURE = "Shared/CreditKit/Tools/Tests/Fixtures/MacroPackage.swift"

  def test_macro_packages_are_linked_but_not_shipped
    targets = package_targets(FIXTURE)
    linked = targets.values.flat_map { |target| target["packages"] }.uniq
    shipped = shipped_package_identities(targets, ["Shipping"])

    assert_equal %w[fake-runtime fake-syntax], linked
    assert_equal ["fake-runtime"], shipped
    assert_equal "macro", targets.fetch("FixtureMacro").fetch("kind")
  end
end
