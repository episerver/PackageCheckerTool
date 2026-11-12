# Repository setup and release process

## Repository contents

Publish only these files to `episerver/PackageCheckerTool`:

```text
nugetchk.sh
README.md
REPOSITORY_SETUP.md
SECURITY.md
LICENSE
NOTICE.md
.gitignore
.gitattributes
test/test_nugetchk.sh
```

The Site Builder files are not part of the GitHub tool repository.

## Required repository protections

Protect the default branch and tags matching `v*`:

- require pull-request approval for `nugetchk.sh` changes
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
git tag -s v1.1.0 -m "DXP NuGet Version Checker v1.1.0"
git push origin v1.1.0
```

## Run from Kudu SSH

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.1.0/nugetchk.sh" |
  bash
```

## Data handling

The checker prints results to the terminal and removes its temporary workspace automatically. It does not modify the application or persist customer report data.
