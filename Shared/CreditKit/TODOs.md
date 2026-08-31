# CreditKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P2s (Nice to have)
- fix [quick-win]: `github_slug` accepts anything after the host, so a malformed pin becomes a malformed API path instead of a clear error. It captures `.+?` (`Tools/generate-attribution.rb:96-97`) and the result is interpolated straight into `repos/#{slug}/license?ref=#{ref}` (`:88`), so a `location` of `https://github.com/foo/bar?x=y` asks for `repos/foo/bar?x=y/license?ref=…` and fails with whatever `gh` makes of that. Not a security issue: both inputs are repo-controlled (`Package.resolved`, `.agents/external-skills.json`) and `Open3.capture3` passes argv with no shell, so nothing is injectable. Constrain the capture to `[\w.-]+/[\w.-]+` so a bad pin fails as a bad pin. `Tools/Tests/generate_attribution_test.rb` covers the generator but not this path. (pr#140 review; re-verified 2026-08-30)

# Completed issues
