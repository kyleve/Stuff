#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs an attribution report for one app and writes it as a self-contained
# manifest that `CreditKit.AttributionManifest` decodes at runtime.
#
# The report is generated rather than hand-kept, and that is the whole point: a
# hand-maintained list silently goes stale the moment some *other* module adds
# a dependency, whereas a re-run picks it up wherever it landed.
#
# The app declares what to report on; this script knows *source types*, not any
# one repository's paths. Config (paths relative to the repo root):
#
#   {
#     "output": "Where/Where/Resources/attribution.json",
#     "sources": [
#       { "type": "swiftPackageManager", "manifest": "Package.swift",
#         "resolved": "Package.resolved", "shippedFrom": ["WhereUI"] },
#       { "type": "agentSkills", "kind": "developmentTool",
#         "manifest": ".agents/external-skills.json" },
#       { "type": "developmentTools", "kind": "developmentTool",
#         "manifest": ".agents/development-tools.json" }
#     ]
#   }
#
# Source types:
#
#   - `swiftPackageManager` — packages a target actually links via
#     `.product(name:package:)` in the manifest, pinned by the resolved file. A
#     package declared for tooling alone (an architecture linter, say) is never
#     linked and so is deliberately not credited.
#
#     `kind` is **derived, not declared**: `shippedFrom` names the package
#     targets the shipping app and its extensions link, and a package reachable
#     from that closure is a `library` while any other linked package is a
#     `developmentTool`. Linking alone doesn't mean shipping — a snapshot-testing
#     engine is linked by a test-support target and never reaches a device — and
#     crediting one as a `library` would tell a reader their binary contains it.
#   - `agentSkills` — a `./sync-agents` external-skills manifest of
#     `name -> { repo, ref }`. These are not in the binary, but the repository
#     makes copies of them, which is what their licenses ask us to attribute.
#   - `developmentTools` — a manifest of pinned GitHub-hosted tooling the
#     repository depends on but does not link as an SPM package (e.g. TLA+/TLC
#     via `./tla-check`). Entries may carry an optional `version` for display;
#     otherwise the pinned ref's short prefix is used.
#
# Each credit carries its notice **inline**, read at the pinned revision, so one
# decode yields everything needed to discharge the attribution and there is no
# second lookup that can come back empty.
#
# Needs network and an authenticated `gh`. Idempotent — re-run after changing a
# dependency or running `./sync-agents --update`. Prefer the repo-root wrapper:
#   ./attribution
# or point it at one config directly:
#   ruby Shared/CreditKit/Tools/generate-attribution.rb <config.json>
#
# `--check` verifies a committed report still matches what the repo declares,
# without writing anything. It makes **no network calls** — every field it
# compares comes from files in the repo — so it is cheap enough to gate CI, which
# is the only thing that actually stops a stale report from shipping.

require "json"
require "fileutils"
require "open3"

ROOT = File.expand_path("../../..", __dir__)

def fail_with(message)
  abort "generate-attribution: #{message}"
end

# The `kind` values `SoftwareCredit.Kind` decodes. A declared one is checked up
# front because a typo would otherwise produce a report that generates fine and
# commits fine, then fails to decode inside the app — surfacing as a fault and a
# debug trap on the About screen, a long way from the config line that caused it.
KIND_LIBRARY = "library"
KIND_DEVELOPMENT_TOOL = "developmentTool"
KINDS = [KIND_LIBRARY, KIND_DEVELOPMENT_TOOL].freeze

# GitHub's license endpoint resolves the notice's filename for us (LICENSE,
# LICENSE.md, COPYING, …) and reports the license's title alongside it, so one
# call answers both "what license" and "what text".
#
# Always read it at the pinned revision rather than the default branch: a
# notice we ship should be the one that governs the revision we actually use,
# and upstream edits it (a bumped copyright year, a relicense) between releases.
def github_license(slug, ref)
  out, err, status = Open3.capture3("gh", "api", "repos/#{slug}/license?ref=#{ref}")
  fail_with("could not read the license for #{slug}: #{err.strip}") unless status.success?
  payload = JSON.parse(out)
  text = payload["content"].to_s.unpack1("m")
  fail_with("#{slug} reports a license with no text") if text.strip.empty?
  { "name" => payload.dig("license", "name") || "See notice", "text" => text }
end

def github_slug(location)
  location[%r{github\.com[:/](.+?)(?:\.git)?/?\z}, 1]
end

# The fields of a credit that come from files already in the repo. The notice is
# deliberately not one of them: it is the only field needing the network, which
# is what lets `--check` derive the whole expected report offline.
NOTICE_FREE_KEYS = %w[name kind version homepageURL].freeze

def credit(name:, kind:, version:, slug:, ref:)
  {
    "name" => name,
    "kind" => kind,
    "version" => version,
    "homepageURL" => "https://github.com/#{slug}",
    # Carried for the notice fetch, then dropped before the report is written.
    "slug" => slug,
    "ref" => ref,
  }
end

def notice_free(entry)
  NOTICE_FREE_KEYS.to_h { |key| [key, entry[key]] }
end

def describe(entry)
  "#{entry["kind"]}: #{entry["name"]} #{entry["version"]}"
end

def read_json(relative_path, source_type)
  path = File.join(ROOT, relative_path)
  fail_with("#{source_type}: no file at #{relative_path}") unless File.exist?(path)
  JSON.parse(File.read(path))
end

# A target declaration, as distinct from a `.target(name:)` *dependency* entry:
# only the declaration puts `name:` on its own line. Keying off that rather than
# indentation keeps the parse independent of how deeply the array is nested.
TARGET_DECLARATION = /\.(?:target|testTarget|executableTarget)\(\s*\n\s*name:\s*"([^"]+)"/
TARGET_DEPENDENCY = /\.target\(name:\s*"([^"]+)"/
PRODUCT_DEPENDENCY = /\.product\(\s*name:\s*"[^"]+",\s*package:\s*"([^"]+)"/

# The manifest's target graph: each target with the sibling targets and the
# external packages (by SPM identity — the lowercased `package:` name) it links.
def package_targets(manifest_path)
  path = File.join(ROOT, manifest_path)
  fail_with("swiftPackageManager: no manifest at #{manifest_path}") unless File.exist?(path)
  text = File.read(path)
  declarations = text.to_enum(:scan, TARGET_DECLARATION).map { Regexp.last_match }
  fail_with("swiftPackageManager: no targets found in #{manifest_path}") if declarations.empty?

  declarations.each_with_index.to_h do |declaration, index|
    # Everything up to the next declaration is this target's body.
    body = text[declaration.end(0)...(declarations[index + 1]&.begin(0) || text.length)]
    [
      declaration[1],
      {
        "targets" => body.scan(TARGET_DEPENDENCY).flatten,
        "packages" => body.scan(PRODUCT_DEPENDENCY).flatten.map(&:downcase),
      },
    ]
  end
end

# Package identities reachable from `roots` — the ones that end up in the app
# binary, as opposed to those linked only by test-support or tooling targets.
def shipped_package_identities(targets, roots)
  unknown = roots - targets.keys
  fail_with("swiftPackageManager: shippedFrom names no such target: #{unknown.join(", ")}") unless unknown.empty?

  visited = []
  queue = roots.dup
  shipped = []
  until queue.empty?
    name = queue.shift
    next if visited.include?(name)
    visited << name
    target = targets[name]
    next unless target
    shipped.concat(target["packages"])
    queue.concat(target["targets"])
  end
  shipped.uniq
end

def swift_package_manager_credits(source)
  targets = package_targets(source.fetch("manifest"))
  linked = targets.values.flat_map { |target| target["packages"] }.uniq
  fail_with("swiftPackageManager: no linked packages found") if linked.empty?
  shipped = shipped_package_identities(targets, source.fetch("shippedFrom"))

  resolved = read_json(source.fetch("resolved"), "swiftPackageManager")
  pins = resolved.fetch("pins").select { |pin| linked.include?(pin["identity"]) }
  missing = linked - pins.map { |pin| pin["identity"] }
  fail_with("#{missing.join(", ")} linked but unresolved") unless missing.empty?

  pins.map do |pin|
    slug = github_slug(pin.fetch("location"))
    fail_with("#{pin["identity"]} is not hosted on GitHub") unless slug
    state = pin.fetch("state")
    revision = state.fetch("revision")
    credit(
      name: slug.split("/").last,
      kind: shipped.include?(pin["identity"]) ? KIND_LIBRARY : KIND_DEVELOPMENT_TOOL,
      # A branch-pinned package has no version, so fall back to the revision.
      version: state["version"] || revision[0, 12],
      slug: slug,
      ref: revision,
    )
  end
end

def manifest_credits(source, source_type)
  kind = source.fetch("kind")
  read_json(source.fetch("manifest"), source_type).map do |name, entry|
    ref = entry.fetch("ref")
    credit(
      name: name,
      kind: kind,
      version: entry["version"] || ref[0, 12],
      slug: entry.fetch("repo"),
      ref: ref,
    )
  end
end

def agent_skills_credits(source)
  manifest_credits(source, "agentSkills")
end

def development_tools_credits(source)
  manifest_credits(source, "developmentTools")
end

SOURCE_TYPES = {
  "swiftPackageManager" => {
    required: %w[manifest resolved shippedFrom],
    generate: method(:swift_package_manager_credits),
  },
  "agentSkills" => {
    required: %w[manifest kind],
    generate: method(:agent_skills_credits),
  },
  "developmentTools" => {
    required: %w[manifest kind],
    generate: method(:development_tools_credits),
  },
}.freeze

# Checked for every source before any of them runs, so a config mistake costs a
# second rather than surfacing after the first source's network round trips.
def validate_source(source, config_path)
  type = source.fetch("type")
  spec = SOURCE_TYPES[type]
  fail_with("unknown source type #{type.inspect} in #{config_path}") unless spec

  missing = spec[:required] - source.keys
  fail_with("#{type} in #{config_path} is missing #{missing.join(", ")}") unless missing.empty?

  kind = source["kind"]
  return if kind.nil? || KINDS.include?(kind)
  fail_with("unknown kind #{kind.inspect} in #{config_path} (expected #{KINDS.join(" or ")})")
end

def report(config_path, check:)
  config = JSON.parse(File.read(config_path))
  sources = config.fetch("sources")
  fail_with("#{config_path} declares no sources") if sources.empty?

  sources.each { |source| validate_source(source, config_path) }

  credits = sources.flat_map do |source|
    # Sort within a source so the report has a stable order and re-running it
    # produces no diff when nothing changed. A source can now emit more than one
    # kind, so sort by kind first — otherwise adding a test-only package would
    # reshuffle the shipping libraries around it.
    SOURCE_TYPES.fetch(source.fetch("type"))[:generate]
                .call(source)
                .sort_by { |entry| [KINDS.index(entry["kind"]), entry["name"].downcase] }
  end
  fail_with("#{config_path} produced no credits") if credits.empty?

  # `SoftwareCredit` is `Identifiable` by name, so a collision hands SwiftUI two
  # rows sharing one id. It takes only two orgs publishing the same repo name,
  # since a library's name is its repo basename. Compared case-insensitively:
  # a pair differing only in case is legal but unreadable in a list.
  collisions = credits.group_by { |entry| entry["name"].downcase }
                      .select { |_, entries| entries.size > 1 }
                      .keys
  fail_with("duplicate credit name(s): #{collisions.join(", ")}") unless collisions.empty?

  return check_report(credits, config.fetch("output")) if check

  write_report(credits, config.fetch("output"))
end

def write_report(credits, output_path)
  output = File.join(ROOT, output_path)
  entries = credits.map do |entry|
    notice_free(entry).merge("license" => github_license(entry["slug"], entry["ref"]))
  end
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, "#{JSON.pretty_generate({ "credits" => entries })}\n")

  puts "#{output_path}: #{entries.count} credit(s)"
  entries.each { |entry| puts "  #{describe(entry)}" }
end

# Fails when the committed report disagrees with what the repo now declares.
#
# Runs entirely offline, which is the whole reason it can gate CI: every field
# it compares is derived from `Package.swift`, `Package.resolved`, and the skills
# and development-tools manifests. It can't re-read a notice, but it doesn't need
# to — a notice is
# fetched at the pinned revision, so a matching revision means matching text by
# construction, and the notice being *present* is checked here directly.
def check_report(credits, output_path)
  path = File.join(ROOT, output_path)
  fail_with("#{output_path} does not exist — run ./attribution") unless File.exist?(path)
  committed = JSON.parse(File.read(path))["credits"]
  fail_with("#{output_path} carries no credits — run ./attribution") if committed.nil? || committed.empty?

  expected = credits.map { |entry| notice_free(entry) }
  actual = committed.map { |entry| notice_free(entry) }
  unless expected == actual
    lines = (expected - actual).map { |entry| "  missing:  #{describe(entry)}" } +
            (actual - expected).map { |entry| "  unexpected: #{describe(entry)}" }
    # Same list, different order, is still a mismatch worth reporting plainly.
    lines << "  (same credits, different order)" if lines.empty?
    fail_with("#{output_path} is stale — run ./attribution\n#{lines.join("\n")}")
  end

  bare = committed.select { |entry| entry.dig("license", "text").to_s.strip.empty? }
                  .map { |entry| entry["name"] }
  fail_with("#{output_path}: no notice for #{bare.join(", ")}") unless bare.empty?

  puts "#{output_path}: up to date (#{committed.count} credit(s))"
end

check = !ARGV.delete("--check").nil?
configs = ARGV
fail_with("usage: generate-attribution.rb [--check] <config.json>...") if configs.empty?
configs.each do |config|
  fail_with("no config at #{config}") unless File.exist?(config)
  report(config, check: check)
end
