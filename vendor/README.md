# Vendor files

This directory stores third-party installer scripts, helper scripts, and static config files used by `tool.sh`.

The menu should fetch these files from `https://raw.githubusercontent.com/Taylor000/tool/master/vendor/...` instead of the original project raw URLs.

Notes:

- Docker images are intentionally not mirrored.
- Large or version-sensitive software binaries may still be downloaded from their official GitHub releases, package mirrors, or project download endpoints.
- The v2node installer is an exception: its binaries are pinned to the self-owned `Taylor000/tool` `v2.1.11` release and verified with fixed SHA-256 values.
- DD system image URLs are intentionally left as external image URLs unless explicitly mirrored later.
