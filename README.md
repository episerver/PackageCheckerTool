# Optimizely DXP NuGet Health Checker

A purpose-built Bash utility for Azure App Service Linux and Kudu SSH. It reads a deployed application's `.deps.json`, checks EPiServer and Optimizely package versions, highlights potentially relevant fixes, prints a terminal summary, and writes JSON reports.

## Quick start

Run the protected `v1.0.0` release from the public Optimizely repository:

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | bash
```

Print the results and save the same terminal output:

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | \
  bash 2>&1 | tee nugetchk_terminal_report.txt
```

Show the available release-note summaries:

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | \
  bash -s -- --notes
```

Use a specific dependency file:

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" | \
  bash -s -- --deps /home/site/wwwroot/MyApp.deps.json
```

## What it does

1. Locates the deployed application's `.deps.json` file.
2. Extracts installed `EPiServer.*` and `Optimizely.*` package versions.
3. Queries the Optimizely NuGet registration feed for current versions.
4. Reads the archived Optimizely release-note pages.
5. Flags notes mentioning memory, performance, timeout, deadlock, thread, or CPU concerns.
6. Prints a terminal table and writes reusable reports.

The checker is read-only with respect to the deployed application. It does not install, remove, or upgrade application packages.

## Options

```text
-n, --notes             Show release-note summaries
-f, --deps FILE         Select a specific .deps.json file
-o, --output-dir DIR    Select the report and cache directory
    --refresh           Ignore an existing release-note cache
-d, --debug             Show diagnostic messages
-h, --help              Show usage
```

## Output

- `nugetchk_report.json` — complete package and recommendation report
- `known_issues.json` — keyword-matched release-note records
- `<AppName>_nugetchk_notes.zip` — optional release-note cache
- `nugetchk_terminal_report.txt` — created when the command uses `tee`

When the script is piped into Bash, reports are written to the current directory. Set `NUGETCHK_OUTPUT_DIR` or use `--output-dir` to choose another location.

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

## Release-note limitation

The World release-note archive was frozen in May 2024. Package version checks remain current, but packages released later may not have issue details in that archive.

## Tests

```bash
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
