# sdkcraft.yaml Reference

Complete field reference for SDK definition files.

## Top-Level Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | YES | SDK identifier, lowercase with hyphens |
| `version` | string | YES* | Quote it: `"1.0"`. Use `adopt-info` instead for VERSION-file workflow |
| `adopt-info` | string | — | Name of the part that calls `craftctl set version`. Replaces `version` |
| `title` | string | — | Human-readable title |
| `summary` | string | — | One line, max 79 chars |
| `description` | string | — | Multi-line YAML string, max ~100 words |
| `license` | string | — | SPDX identifier or URL |
| `base` | string | — | `ubuntu@22.04` or `ubuntu@24.04`. SDK can only join matching workshop |
| `build-base` | string | — | Build-time base. Required if no `base` |
| `platforms` | object | YES | Where SDK can be built and installed |
| `parts` | object | — | Build components |
| `plugs` | object | — | Resources SDK consumes |
| `slots` | object | — | Resources SDK provides |

*Either `version` or `adopt-info` is required.

## version vs adopt-info

**Hardcoded version** (not recommended for Renovate-managed SDKs):
```yaml
name: myapp
version: "1.0.0"
```

**Dynamic version from VERSION file** (recommended):
```yaml
name: myapp
adopt-info: myapp   # must match a part name

parts:
  myapp:
    plugin: nil
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
```

## Platforms

### Multi-base (supports multiple Ubuntu versions)

```yaml
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:
```

No `base` or `build-base` needed. CI uses `--platform`.

### Single-base, multi-arch

```yaml
build-base: ubuntu@24.04
platforms:
  amd64:
    build-on: [amd64]
    build-for: [amd64]
  arm64:
    build-on: [amd64]
    build-for: [arm64]
```

### Single-base, single-arch (simplest)

```yaml
build-base: ubuntu@24.04
platforms:
  amd64:
    build-on: [amd64]
    build-for: [amd64]
```

## Parts

### Plugin types

| Plugin | Use case | Examples |
|---|---|---|
| `nil` | No build; version-only or hook-based install | go, rocm, dotnet, vscode-remote |
| `dump` | Copy pre-built files | ollama, opencode, zephyr, ros2 |
| `npm` | Build npm packages with optional bundled Node.js | copilot, claude-code, codex |
| `rust` | Build from Rust source with cargo | rustup, uv |
| `cmake` | Build C/C++ with CMake | openvino |
| `make` | Build with Makefile | node |

### Part fields

```yaml
parts:
  mypart:
    plugin: dump
    source: .                          # Source location (., URL, or git repo)
    source-type: local                 # local, tar, git, file
    source-tag: $CRAFT_PROJECT_VERSION # Git tag for source
    build-packages: [gcc, pkg-config]  # Apt packages needed at build time
    build-snaps: [astral-uv]           # Snaps needed at build time
    build-environment:
      - KEY: "value"                   # Environment vars during build
    override-pull: |                   # Custom pull logic
      # ...
    override-build: |                  # Custom build logic
      # ...
    organize:                          # Rename/move files in staging
      myapp: usr/bin/myapp
    stage:                             # Files to include in stage
      - -include                       # Prefix with - to exclude
    prime:                             # Files to include in final SDK
      - bin/myapp
```

## Plugs

```yaml
plugs:
  my-cache:
    interface: mount
    workshop-target: /home/workshop/.cache/mytool  # Required for mount
    mode: 0o755                                     # Optional
    read-only: false                                # Optional

  gpu:
    interface: gpu

  desktop:
    interface: desktop

  ssh-agent:
    interface: ssh
```

## Slots

```yaml
slots:
  my-server:
    interface: tunnel
    endpoint: 8080                    # Port number for tunnel

  shared-data:
    interface: mount
    workshop-source: /home/workshop/shared-dir  # Path inside workshop
```

## Complete Example — Simple binary SDK

```yaml
name: opencode
adopt-info: opencode
build-base: ubuntu@24.04
summary: The OpenCode SDK
description: |
  This SDK provides OpenCode for AI-assisted coding within a workshop.
  Configuration and application data are persisted between workshop updates.
license: MIT
platforms:
  amd64:
    build-on: [amd64]
    build-for: [amd64]

plugs:
  opencode-data:
    interface: mount
    workshop-target: /home/workshop/.local/share/opencode
  opencode-config:
    interface: mount
    workshop-target: /home/workshop/.config/opencode

parts:
  opencode:
    plugin: dump
    source: .
    source-type: local
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
      curl -fLO "https://github.com/example/tool/releases/download/v${VERSION}/tool-linux-x64.tar.gz"
      tar -xzf "tool-linux-x64.tar.gz" -C "$CRAFT_PART_SRC"
      rm "tool-linux-x64.tar.gz"
    organize:
      opencode: usr/bin/opencode
```

## Complete Example — Service SDK with tunnel

```yaml
name: ollama
adopt-info: ollama
summary: Get up and running with large language models
license: MIT
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:

plugs:
  gpu:
    interface: gpu
  models:
    interface: mount
    workshop-target: /home/workshop/.ollama/models

slots:
  ollama-server:
    interface: tunnel
    endpoint: 11434

parts:
  ollama:
    plugin: dump
    source: .
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
      curl -fLO "https://github.com/ollama/ollama/releases/download/v${VERSION}/ollama-linux-amd64.tar.zst"
      tar -xf "ollama-linux-amd64.tar.zst" -C "$CRAFT_PART_SRC"
      rm "ollama-linux-amd64.tar.zst"
  services:
    plugin: dump
    source: services
    source-type: local
```

## Complete Example — No-parts SDK (hook-based)

```yaml
name: vscode-remote
adopt-info: version
summary: VS Code Remote Development plugin support
description: |
  This SDK enables VS Code Remote Development over SSH in a workshop.
license: GPL-3.0
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:

plugs:
  vscode-server:
    interface: mount
    workshop-target: /home/workshop/.vscode-server
    mode: 0o700

parts:
  version:
    plugin: nil
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
```
