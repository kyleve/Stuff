# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require File.expand_path("../../Shared/CreditKit/Tools/generate-attribution", __dir__)

class GenerateAttributionTest < Minitest::Test
  def test_wrapped_conditional_dependency_is_not_a_target_declaration
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Package.swift"), <<~SWIFT)
        let package = Package(targets: [
          .target(name: "App", dependencies: [
            .target(
              name: "Shared",
              condition: .when(platforms: [.iOS])
            ),
            // A closing parenthesis ) in a comment does not close the target.
            /* Nor does this nested /* comment */ ). */
            .product(name: "Symbols", package: "symbols"),
          ], path: "Sources/(App)"),
          .target(name: "Shared", dependencies: [
            .product(name: "Core", package: "core"),
          ]),
        ])
      SWIFT
      targets = package_targets("Package.swift", root: root)
      assert_equal %w[App Shared], targets.keys
      assert_equal ["Shared"], targets.fetch("App").fetch("targets")
      assert_equal ["symbols"], targets.fetch("App").fetch("packages")
      assert_equal %w[symbols core], shipped_package_identities(targets, ["App"])
    end
  end

  def test_local_products_use_their_own_manifest_source_instead_of_a_remote_pin
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Package.swift"), <<~SWIFT)
        let package = Package(
          dependencies: [.package(path: "Shared/LocalCertificates")],
          targets: [
            .target(
              name: "App",
              dependencies: [
                .product(name: "Certificates", package: "LocalCertificates"),
                .product(name: "Other", package: "remote-package"),
              ]
            )
          ]
        )
      SWIFT
      targets = package_targets("Package.swift", root: root)
      assert_equal ["remote-package"], targets.fetch("App").fetch("packages")
      assert_equal ["remote-package"], shipped_package_identities(targets, ["App"])
    end
  end

  def test_parses_target_and_package_graph_with_shipping_reachability
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Package.swift"), <<~SWIFT)
        let package = Package(
          targets: [
            .target(
              name: "App",
              dependencies: [
                .target(name: "Feature"),
                .product(
                  name: "Runtime",
                  package: "Runtime-Package"
                ),
              ]
            ),
            .target(
              name: "Feature",
              dependencies: [
                .product(name: "FeatureKit", package: "FeatureKit"),
              ]
            ),
            .testTarget(
              name: "AppTests",
              dependencies: [
                .target(name: "App"),
                .product(name: "TestSupport", package: "test-support"),
              ]
            ),
          ]
        )
      SWIFT

      targets = package_targets("Package.swift", root: root)

      assert_equal %w[App Feature AppTests], targets.keys
      assert_equal ["Feature"], targets.fetch("App").fetch("targets")
      assert_equal ["runtime-package"], targets.fetch("App").fetch("packages")
      assert_equal ["featurekit"], targets.fetch("Feature").fetch("packages")
      assert_equal ["test-support"], targets.fetch("AppTests").fetch("packages")
      assert_equal %w[runtime-package featurekit], shipped_package_identities(targets, ["App"])
    end
  end

  def test_rejects_unknown_shipping_roots
    _, error = capture_io do
      assert_raises(SystemExit) do
        shipped_package_identities({ "App" => { "targets" => [], "packages" => [] } }, ["Missing"])
      end
    end

    assert_includes error, "shippedFrom names no such target: Missing"
  end

  def test_validates_source_type_required_fields_and_kind
    invalid_sources = [
      [{ "type" => "imaginary" }, "unknown source type"],
      [{ "type" => "agentSkills", "kind" => "developmentTool" }, "is missing manifest"],
      [
        { "type" => "developmentTools", "kind" => "tool", "manifest" => "tools.json" },
        "unknown kind",
      ],
    ]

    invalid_sources.each do |source, expected|
      _, error = capture_io do
        assert_raises(SystemExit) { validate_source(source, "config.json") }
      end
      assert_includes error, expected
    end
  end

  def test_report_check_accepts_exact_credit_and_rejects_missing_notice
    Dir.mktmpdir do |root|
      entry = credit(
        name: "Library",
        kind: KIND_LIBRARY,
        version: "1.2.3",
        slug: "example/Library",
        ref: "abc123",
      )
      output_path = "Resources/attribution.json"
      absolute_output = File.join(root, output_path)
      FileUtils.mkdir_p(File.dirname(absolute_output))
      File.write(
        absolute_output,
        JSON.generate(
          "credits" => [notice_free(entry).merge("license" => { "name" => "MIT", "text" => "notice" })],
        ),
      )

      stdout, = capture_io { check_report([entry], output_path, root: root) }
      assert_includes stdout, "up to date (1 credit(s))"

      File.write(
        absolute_output,
        JSON.generate(
          "credits" => [notice_free(entry).merge("license" => { "name" => "MIT", "text" => "" })],
        ),
      )
      _, error = capture_io do
        assert_raises(SystemExit) { check_report([entry], output_path, root: root) }
      end
      assert_includes error, "no notice for Library"
    end
  end
end
