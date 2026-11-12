# Optimizely DXP NuGet Version Checker

Checks installed `EPiServer.*` and `Optimizely.*` packages in an Azure App Service Linux environment and compares them with the latest stable versions from the Optimizely NuGet feed.

The tool is read-only, prints results in the terminal, and removes all temporary data when it exits.

To access the terminal to run these commands: Go to the Web App in Azure and navigate to SSH in the left-hand menu.

## Run

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.1.0/nugetchk.sh" | bash
```

Before `v1.1.0` is released, use `main` instead:

```bash
cd /app
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/main/nugetchk.sh" | bash
```

## Options

```text
-f, --deps FILE   Use a specific .deps.json file
-d, --debug       Print diagnostic messages
-h, --help        Show help
```

Example with a specific dependency file:

```bash
curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL \
  "https://raw.githubusercontent.com/episerver/PackageCheckerTool/v1.1.0/nugetchk.sh" | \
  bash -s -- --deps /app/MyApp.deps.json
```

## Output

```text
PACKAGE                                  INSTALLED      LATEST         DELTA
-------                                  ---------      ------         -----
EPiServer.Azure                          11.1.1         13.6.0         +2maj, 5min
EPiServer.CMS                            12.34.4        13.6.0         +1maj
EPiServer.CMS.Core                       12.24.1        13.6.0         +1maj
Optimizely.ContentGraph.Cms              4.4.2          4.4.5          +3pat

Total packages scanned:       4
Updates available:            4
Up to date or ahead:          0
Version lookup failures:      0
```

- `INSTALLED` — deployed version
- `LATEST` — latest stable published version
- `DELTA` — every major, minor, or patch component that increased; reset lower components are omitted

## Requirements

- Bash 4+
- curl
- HTTPS access to `nuget.optimizely.com`

If jq is unavailable, a temporary checksum-verified jq 1.8.2 binary is downloaded and removed automatically when the checker exits.

## Validate

```bash
bash -n nugetchk.sh
bash test/test_nugetchk.sh
```
