# Security Policy

## Reporting a Vulnerability

If you believe you have found a security vulnerability in this Homebrew tap, the binaries it distributes (`c1-vega-plen`, `c1-vega-en`), the install scripts, or the formula post-install behavior, please report it privately.

**Preferred channel:** [Private vulnerability reporting on [ORGANIZATION_3]](https://github.com/copernicusone/homebrew-vega/security/advisories/new)

**Email fallback:** security@copernicusone.com

Please include:
- A description of the vulnerability and its potential impact
- Steps to reproduce, including the formula version and platform
- Any SHA-256 hashes, URLs, or commit SHAs that help isolate the issue
- Whether the issue is already publicly disclosed elsewhere

We aim to acknowledge new reports within **2 business days** and to ship a fix or mitigation within **30 days** for high-severity issues.

## Supported Versions

| Component | Supported |
|-----------|-----------|
| `c1-vega-plen` (latest published in this tap) | ✅ |
| `c1-vega-en` (latest published in this tap) | ✅ |
| Older patch releases | best-effort only |
| `c1-vega-pl` (retired) | ❌ — please upgrade to `c1-vega-plen` |

## What This Repo Distributes

This repository is a Homebrew tap. Each formula references binary release artifacts hosted on this repository's GitHub Releases page. The binaries themselves are built and signed in the upstream `copernicusone/vega-cli` repository by the `build-release` workflow, and mirrored here for distribution.

Notable invariants enforced by the tap:
- Every formula declares a `sha256` for each platform binary, verified by Homebrew at install time
- Release tags `c1-vega-*-v*` are protected against deletion, force-push, and update
- Formula updates land via PR, CI-gated by `brew style + brew audit --strict`, and require a code-owner approval before merge
- The default branch (`main`) blocks direct pushes; squash-only merges; stale reviews are dismissed on push
- `secret_scanning` and `secret_scanning_push_protection` are enabled

## Out of Scope

- Issues in upstream Homebrew itself — please report those at https://github.com/Homebrew/brew
- Third-party services that the tool integrates with (e.g., the model-hosting provider)
- Self-inflicted misconfiguration (e.g., a user committing a license key to a public repo)

## Acknowledgments

We credit reporters in the corresponding security advisory unless they request anonymity.
