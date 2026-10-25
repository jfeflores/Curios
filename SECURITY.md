# Curios security policy

Curios V1 is a young, local-only macOS application. Security hardening and passing tests are not certification that it is vulnerability-free. Use independent backups and do not treat plaintext task storage as an encrypted vault.

## Reporting

Do not post credentials, personal task exports, calendar information or an uncoordinated exploit in a public issue.

Report privately through [GitHub's vulnerability reporting form](https://github.com/jfeflores/Curios/security/advisories/new), or **Security → Advisories → Report a vulnerability** in `jfeflores/Curios`. Private vulnerability reporting was enabled and verified during publication setup. Include the commit/build, macOS version, impact and a minimal reproduction using synthetic data.

GitHub secret scanning and push protection are enabled for this public repository, and Actions defaults to read-only permissions without permission to approve pull requests. These controls do not detect every credential or vulnerability. If private reporting becomes unavailable, request a private channel without disclosing vulnerability details publicly. No response-time SLA is promised.

## Scope and support

The current V1 source receives best-effort maintenance. There is no older supported production-version matrix or hosted backend. Security fixes should include a regression and a clear release note; new cloud/auth/sync/AI features require a separate threat model and review.

Current protections include private/ACL-aware atomic file handling, bounded inputs, observed-revision and cross-process write coordination, strict confirmed URL capture, privacy-safe notification text, and production exclusion of development screenshot/test hooks. See [the V1 hardening record](docs/V1_HARDENING.md) for evidence and [the original audit](docs/CURIOS_V1_SECURITY_REVIEW.md) for the findings that motivated the work.

## Limits

- Tasks, backups, recovery copies and exports remain unencrypted. OS permissions do not protect against same-user malware or administrators, and deletion does not securely erase older copies/backups.
- Atomic replacement and stale-write rejection are not cloud synchronization, automatic conflict merging or redundant backup.
- macOS controls permission prompts, notification previews/delivery and background execution. Real-device permission/delivery testing is not replaced by pure planning tests.
- Developer builds are ad-hoc signed, not notarized distributor releases. No production App Sandbox/Developer ID identity is configured by this source release.
- The registered capture schemes are not authenticated remote APIs; no destructive/read-export URL endpoints are provided. Do not include secrets in URLs.

## Contributors and publication

Never commit credentials, signing material, real task exports/databases, private screenshots, proprietary application binaries/assets, or raw reverse-engineering/decompiler evidence. Keep `.analysis/`, `.build/` and `build/` private. Use synthetic fixtures.

Review the exact Git index and every commit being pushed; `.gitignore` cannot protect already tracked or force-added content, manual attachments or whole-folder ZIP uploads. Use a dedicated secret scan, minimal CI permissions, trusted pinned actions and applicable GitHub push protection. If a credential is exposed, revoke/rotate it first: removing a file/history does not invalidate the credential or erase copies.

Original project code/documentation is Apache-2.0; that license does not license another vendor's binaries, artwork, SDKs or trademarks. Contributors must have rights to submit their work.
