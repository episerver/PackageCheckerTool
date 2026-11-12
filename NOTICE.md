# Third-party notices

The Optimizely DXP NuGet Health Checker is maintained as an original implementation in the `episerver/PackageCheckerTool` repository.

## jq

When jq is not already available, the checker can download an official jq binary from the `jqlang/jq` project. The binary is verified against a pinned SHA-256 checksum before execution. jq is distributed under its own license and remains the property of its respective copyright holders.

If an internal copy of jq is redistributed with this project, include all notices and license text required by the jq project.

## External data sources

The checker reads public package metadata and release-note information from Optimizely-operated services. Retrieved metadata is not incorporated into this repository and remains subject to the terms applicable to those services.
