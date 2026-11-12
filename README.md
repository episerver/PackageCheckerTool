# Optimizely DXP NuGet Health Checker

A purpose-built Bash utility for Azure App Service Linux and Kudu SSH. It reads a deployed application's `.deps.json`, checks EPiServer and Optimizely package versions, highlights potentially relevant fixes, and prints a terminal summary.

## Customer-safe default

**The checker does not persist files by default.** It uses a temporary workspace while running and removes that workspace automatically when it exits. The deployed application and its packages are never modified.

## Quick start
Navigate to Azure > SSH ()
Run the protected `v1.0.0` release from the application directory:

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | bash
```

Show all available release-note summaries in the terminal:

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | \
  bash -s -- --notes
```

Use a specific dependency file:

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | \
  bash -s -- --deps /app/MyApp.deps.json
```

Until the first release tag is created, replace `v1.0.0` with `main` for testing only.

## What it does

1. Locates the deployed application's `.deps.json` file, searching `/app` by default with `/home/site/wwwroot` as a compatibility fallback.
2. Extracts installed `EPiServer.*` and `Optimizely.*` package versions.
3. Queries the Optimizely NuGet registration feed for current stable versions.
4. Reads the archived Optimizely release-note pages.
5. Flags notes mentioning memory, performance, timeout, deadlock, thread, or CPU concerns.
6. Prints a copyable table and summary directly in the terminal.

## Options

```text
-n, --notes             Show release-note summaries
-f, --deps FILE         Select a specific .deps.json file
-o, --output-dir DIR    Explicitly persist reports and cache in a directory
    --save-reports DIR  Same as --output-dir; persistence is opt-in
    --refresh           Ignore an existing persisted release-note cache
-d, --debug             Show diagnostic messages
-h, --help              Show usage
```

## Optional report persistence

Persistent reports are disabled by default. If an authorized workflow specifically requires files, opt in explicitly:

```bash
bash nugetchk.sh --save-reports /approved/output/directory
```

This creates:

- `nugetchk_report.json`
- `known_issues.json`
- `<AppName>_nugetchk_notes.zip` when zip is available

Do not enable persistence in a customer environment unless the location and retention have been approved.

## Dependencies and network access

Required commands:

- Bash 4+
- curl
- standard Linux tools such as `find`, `sort`, `awk`, and `sed`

If jq is unavailable, the checker downloads the official jq 1.8.2 Linux binary over HTTPS and verifies its pinned SHA-256 checksum before execution. To use an approved internal binary instead, set both:

```bash
export NUGETCHK_JQ_URL="https://approved.example/jq-linux-amd64"
export NUGETCHK_JQ_SHA256="EXPECTED_SHA256"
```

Runtime HTTPS destinations:

- `nuget.optimizely.com`
- `world.optimizely.com`
- `github.com/jqlang/jq` only when jq is missing and no internal URL is supplied

When jq is missing, its verified helper binary is placed only in the temporary workspace and removed automatically when the checker exits.

## Release-note limitation

The World release-note archive was frozen in May 2024. Package version checks remain current, but packages released later may not have issue details in that archive.

## Tests

```bash
bash -n nugetchk.sh
bash test/test_nugetchk.sh
```

## Repository files

```text
nugetchk.sh
README.md
REPOSITORY_SETUP.md
SECURITY.md
LICENSE
NOTICE.md
.gitignore
.gitattributes
sample_nugetchk_report.json
test/test_nugetchk.sh
```
