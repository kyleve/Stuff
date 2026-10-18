# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require_relative "../generate-attribution"

# A shipping target links a macro which links a host-only syntax package.
# Credit both dependencies, but never classify the macro dependency as shipped.
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

  def test_explicit_notice_path_uses_the_pinned_revision
    status = Struct.new(:success?).new(true)
    response = [{ "content" => ["Pinned license notice"].pack("m0") }.to_json, "", status]
    calls = []
    Open3.stub(:capture3, ->(*args) { calls << args; response }) do
      notice = github_license("example/tool", "pinned-revision", "nested/LICENSE")
      assert_equal "Pinned license notice", notice.fetch("text")
      assert_equal "See notice", notice.fetch("name")
    end
    assert_equal [["gh", "api", "repos/example/tool/contents/nested/LICENSE?ref=pinned-revision"]], calls
  end
end
