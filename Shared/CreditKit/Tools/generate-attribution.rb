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
#       { "type": "swiftPackageManager", "kind": "library",
#         "manifest": "Package.swift", "resolved": "Package.resolved" },
#       { "type": "agentSkills", "kind": "developmentTool",
#         "manifest": ".agents/external-skills.json" }
#     ]
#   }
#
# Source types:
#
#   - `swiftPackageManager` — packages a target actually links via
#     `.product(name:package:)` in the manifest, pinned by the resolved file. A
#     package declared for tooling alone (an architecture linter, say) is never
#     linked and so is deliberately not credited.
#   - `agentSkills` — a `./sync-agents` external-skills manifest of
#     `name -> { repo, ref }`. These are not in the binary, but the repository
#     makes copies of them, which is what their licenses ask us to attribute.
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

require "json"
require "fileutils"
require "open3"

ROOT = File.expand_path("../../..", __dir__)

def fail_with(message)
  abort "generate-attribution: #{message}"
end

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

def credit(name:, kind:, version:, slug:, ref:)
  {
    "name" => name,
    "kind" => kind,
    "version" => version,
    "homepageURL" => "https://github.com/#{slug}",
    "license" => github_license(slug, ref),
  }
end

def read_json(relative_path, source_type)
  path = File.join(ROOT, relative_path)
  fail_with("#{source_type}: no file at #{relative_path}") unless File.exist?(path)
  JSON.parse(File.read(path))
end

# Packages some target actually links, by SPM identity (the lowercased package
# name as it appears in `.product(name:package:)`).
def linked_package_identities(manifest_path)
  path = File.join(ROOT, manifest_path)
  fail_with("swiftPackageManager: no manifest at #{manifest_path}") unless File.exist?(path)
  File.read(path)
      .scan(/\.product\(\s*name:\s*"[^"]+",\s*package:\s*"([^"]+)"/)
      .flatten.map(&:downcase).uniq
end

def swift_package_manager_credits(source)
  kind = source.fetch("kind")
  linked = linked_package_identities(source.fetch("manifest"))
  fail_with("swiftPackageManager: no linked packages found") if linked.empty?

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
      kind: kind,
      # A branch-pinned package has no version, so fall back to the revision.
      version: state["version"] || revision[0, 12],
      slug: slug,
      ref: revision,
    )
  end
end

def agent_skills_credits(source)
  kind = source.fetch("kind")
  read_json(source.fetch("manifest"), "agentSkills").map do |name, entry|
    ref = entry.fetch("ref")
    credit(
      name: name,
      kind: kind,
      version: ref[0, 12],
      slug: entry.fetch("repo"),
      ref: ref,
    )
  end
end

SOURCE_TYPES = {
  "swiftPackageManager" => method(:swift_package_manager_credits),
  "agentSkills" => method(:agent_skills_credits),
}.freeze

def report(config_path)
  config = JSON.parse(File.read(config_path))
  sources = config.fetch("sources")
  fail_with("#{config_path} declares no sources") if sources.empty?

  credits = sources.flat_map do |source|
    type = source.fetch("type")
    generate = SOURCE_TYPES[type]
    fail_with("unknown source type #{type.inspect} in #{config_path}") unless generate
    # Sort within a source so the report has a stable order and re-running it
    # produces no diff when nothing changed.
    generate.call(source).sort_by { |entry| entry["name"].downcase }
  end
  fail_with("#{config_path} produced no credits") if credits.empty?

  output = File.join(ROOT, config.fetch("output"))
  FileUtils.mkdir_p(File.dirname(output))
  File.write(output, "#{JSON.pretty_generate({ "credits" => credits })}\n")

  puts "#{config.fetch("output")}: #{credits.count} credit(s)"
  credits.each { |entry| puts "  #{entry["kind"]}: #{entry["name"]} #{entry["version"]}" }
end

configs = ARGV
fail_with("usage: generate-attribution.rb <config.json>...") if configs.empty?
configs.each do |config|
  fail_with("no config at #{config}") unless File.exist?(config)
  report(config)
end
