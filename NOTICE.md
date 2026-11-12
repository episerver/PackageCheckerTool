# Third-party notices

The Optimizely DXP NuGet Version Checker is maintained as an original implementation in the `episerver/PackageCheckerTool` repository.

## jq

When jq is not already available, the checker can download an official jq binary from the `jqlang/jq` project. The binary is verified against a pinned SHA-256 checksum before execution. jq is distributed under its own license and remains the property of its respective copyright holders.

If an internal copy of jq is redistributed with this project, include all notices and license text required by the jq project.

## External data source

The checker reads public package metadata from the Optimizely NuGet service. Retrieved metadata is used only during execution and is not incorporated into the repository or persisted in the customer environment.
