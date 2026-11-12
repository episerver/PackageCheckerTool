# Repository setup and release process

## Repository contents

Publish only the terminal-tool files to `episerver/PackageCheckerTool`:

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

The Site Builder files (`index.html`, `app.js`, `styles.css`, and generated brand files) are not part of the GitHub tool repository.

## Required repository protections

Protect the default branch and tags matching `v*`:

- require a pull request and approval for `nugetchk.sh` changes
- block force pushes
- restrict who can push or bypass reviews
- prevent release tags from being changed or deleted
- enable private vulnerability reporting

## Validate before release

```bash
bash -n nugetchk.sh
bash test/test_nugetchk.sh
```

If ShellCheck is available:

```bash
shellcheck nugetchk.sh test/test_nugetchk.sh
```

## Create the release tag

```bash
git tag -s v1.0.0 -m "DXP NuGet Health Checker v1.0.0"
git push origin v1.0.0
```

Protect the tag before publishing the terminal command.

## Run from Kudu SSH

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" |
  bash
```

Terminal plus a downloadable text report:

```bash
cd /home/site/wwwroot
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh" |
  bash 2>&1 | tee nugetchk_terminal_report.txt
```

## Optional integrity verification

For environments requiring an explicit checksum, publish the reviewed SHA-256 value with the release:

```bash
EXPECTED_SHA256="VALUE_FROM_THE_APPROVED_RELEASE"
SCRIPT_URL="https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.0.0/nugetchk.sh"
TEMP_SCRIPT=$(mktemp)

curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "$SCRIPT_URL" -o "$TEMP_SCRIPT"
printf '%s  %s\n' "$EXPECTED_SHA256" "$TEMP_SCRIPT" | sha256sum -c -
bash "$TEMP_SCRIPT" --output-dir /home/site/wwwroot
STATUS=$?
rm -f "$TEMP_SCRIPT"
test "$STATUS" -eq 0
```

## Data handling

The default command prints results to the terminal and removes its temporary workspace automatically. It does not persist customer report data.

Persistent JSON reports are available only through the explicit opt-in option:

```bash
bash nugetchk.sh --save-reports /approved/output/directory
```

Do not enable report persistence in a customer environment without approval.
