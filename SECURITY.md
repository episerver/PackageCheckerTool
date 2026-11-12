# Security policy

## Supported version

Only the latest tagged release is supported. Run a protected, versioned tag rather than the mutable default branch.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use GitHub's private vulnerability reporting or contact the repository's Optimizely maintainers through an approved internal security channel.

Include:

- affected release tag
- steps to reproduce
- expected and actual behavior
- potential impact
- any suggested mitigation

Do not include customer data, credentials, access tokens, or production configuration in a report.

## Runtime data handling

- Terminal-only operation is the default.
- Temporary working data is removed automatically when the checker exits.
- Persistent reports require the explicit `--save-reports DIR` or `--output-dir DIR` option.
- The checker does not modify deployed application packages.

## Supply-chain controls

- Protect the default branch and `v*` release tags.
- Require pull-request review for changes to `nugetchk.sh`.
- Run the checker from a versioned tag or verified commit.
- The optional jq download is restricted to HTTPS and verified with a pinned SHA-256 checksum before execution.
- Never add credentials or customer-specific information to the script or generated sample files.
