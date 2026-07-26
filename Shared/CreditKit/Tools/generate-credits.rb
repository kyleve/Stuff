#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates CreditKit's `credits.json` manifest and vendors the license notice
# for every third-party work the project uses.
#
# It derives the list rather than trusting a hand-kept one, which is the point:
# a package linked by *any* module is credited the next time this runs, so no
# module has to remember to vend a credit. Two inputs, one per credit kind:
#
#   - `Package.swift` + `Package.resolved` -> `library` credits. Only packages
#     a target actually links via `.product(name:package:)` count; a package
#     declared for tooling alone (BumperBowling, and swift-syntax underneath it)
#     never reaches the binary and so is deliberately not credited.
#   - `.agents/external-skills.json` -> `developmentTool` credits. These are the
#     agent skills `./sync-agents` vendors into `.agents/skills/`. They are not
#     in the app, but we do make copies of them, which is what their licenses
#     ask us to attribute.
#
# and writes, into `Sources/Resources/`:
#   - `credits.json` — the manifest `CreditCatalog` decodes: `{ name, kind,
#     version, homepageURL?, licenseName, licenseResource }`, libraries first,
#     each group alphabetical.
#   - `Licenses/<name>.txt` — the verbatim notice, fetched from the project's
#     GitHub repository (which also reports the license's title).
#
# Needs network and an authenticated `gh`. Idempotent: re-run after changing a
# dependency or running `./sync-agents --update`. From the repo root:
#   ruby Shared/CreditKit/Tools/generate-credits.rb

require "json"
require "fileutils"
require "open3"

ROOT = File.expand_path("../../..", __dir__)
RESOURCES = File.expand_path("../Sources/Resources", __dir__)
LICENSES_DIR = File.join(RESOURCES, "Licenses")

def fail_with(message)
  abort "generate-credits: #{message}"
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
  [payload.dig("license", "name") || "See notice", text]
end

def github_slug(location)
  location[%r{github\.com[:/](.+?)(?:\.git)?/?\z}, 1]
end

# Packages some target actually links, by SPM identity (lowercased package name
# as it appears in `.product(name:package:)`).
def linked_package_identities
  manifest = File.read(File.join(ROOT, "Package.swift"))
  manifest.scan(/\.product\(\s*name:\s*"[^"]+",\s*package:\s*"([^"]+)"/)
          .flatten.map(&:downcase).uniq
end

def library_credits
  resolved = JSON.parse(File.read(File.join(ROOT, "Package.resolved")))
  linked = linked_package_identities
  fail_with("no linked packages found in Package.swift") if linked.empty?

  pins = resolved.fetch("pins").select { |pin| linked.include?(pin["identity"]) }
  missing = linked - pins.map { |pin| pin["identity"] }
  fail_with("#{missing.join(", ")} linked but absent from Package.resolved") unless missing.empty?

  pins.map do |pin|
    location = pin.fetch("location")
    slug = github_slug(location) || fail_with("#{pin["identity"]} is not a GitHub package")
    state = pin.fetch("state")
    revision = state.fetch("revision")
    # A branch-pinned package has no version, so fall back to the short revision.
    version = state["version"] || revision[0, 12]
    name = slug.split("/").last
    license_name, text = github_license(slug, revision)
    { name: name, kind: "library", version: version,
      homepage: "https://github.com/#{slug}", license_name: license_name, text: text }
  end
end

def development_tool_credits
  path = File.join(ROOT, ".agents", "external-skills.json")
  return [] unless File.exist?(path)

  JSON.parse(File.read(path)).map do |name, entry|
    slug = entry.fetch("repo")
    license_name, text = github_license(slug, entry.fetch("ref"))
    { name: name, kind: "developmentTool", version: entry.fetch("ref")[0, 12],
      homepage: "https://github.com/#{slug}", license_name: license_name, text: text }
  end
end

credits = library_credits.sort_by { |credit| credit[:name].downcase } +
          development_tool_credits.sort_by { |credit| credit[:name].downcase }
fail_with("no credits generated") if credits.empty?

FileUtils.mkdir_p(LICENSES_DIR)
# Rewrite the vendored notices from scratch so a dropped dependency doesn't
# leave a stale license behind for a credit that no longer exists.
FileUtils.rm_f(Dir.glob(File.join(LICENSES_DIR, "*.txt")))

manifest = credits.map do |credit|
  resource = credit[:name]
  File.write(File.join(LICENSES_DIR, "#{resource}.txt"), credit[:text])
  {
    "name" => credit[:name],
    "kind" => credit[:kind],
    "version" => credit[:version],
    "homepageURL" => credit[:homepage],
    "licenseName" => credit[:license_name],
    "licenseResource" => resource,
  }
end

File.write(File.join(RESOURCES, "credits.json"), "#{JSON.pretty_generate(manifest)}\n")
puts "Wrote #{manifest.count} credit(s) and #{manifest.count} license notice(s)."
manifest.each { |credit| puts "  #{credit["kind"]}: #{credit["name"]} #{credit["version"]}" }
