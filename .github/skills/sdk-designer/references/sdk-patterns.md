# SDK Patterns Reference

Detailed decision trees and patterns extracted from all reference SDKs.

## Platform Layout Decision

```
Does the SDK need to run on multiple Ubuntu versions?
├── YES → Multi-base: list each ubuntu@XX.04:arch under platforms
│         Use --platform flag in CI upload.yml
│         Example: node-sdk, rust-sdk, vscode-remote-sdk
│
└── NO → Does it need multiple architectures?
         ├── YES → Single build-base + explicit build-on/build-for
         │         Use --build-for flag (default) in CI
         │         Example: go-sdk (amd64, arm64, riscv64)
         │
         └── NO → Single build-base + simple platform
                   Example: copilot-sdk, opencode-sdk
```

### Multi-base platform format

```yaml
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:
```

No `build-base` field. CI uses `--platform` flag.

### Single-base with multi-arch

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

### Single-base, single-arch

```yaml
build-base: ubuntu@24.04
platforms:
  amd64:
    build-on: [amd64]
    build-for: [amd64]
```

Or the minimal form:

```yaml
build-base: ubuntu@24.04
platforms:
  amd64:
```

## Parts Strategy Decision

```
How is the upstream software distributed?
│
├── Pre-built binary tarball (Go, Ollama, OpenCode)
│   → plugin: nil or plugin: dump
│   → override-pull: curl + tar
│
├── npm package (Copilot CLI, Claude Code, Codex)
│   → plugin: npm
│   → npm-include-node: true
│   → override-pull: curl from registry.npmjs.org + tar
│
├── Rust source (uv, rustup)
│   → plugin: rust
│   → source from git
│
├── C/C++ source (OpenVINO)
│   → plugin: cmake
│   → git clone in override-pull
│
├── Python package (JupyterLab)
│   → plugin: nil (install at runtime via pip/uv in hooks)
│   → Just set version in override-pull
│
├── System packages via apt (ROCm, .NET, ROS 2)
│   → plugin: nil
│   → Install in hooks/setup-base via apt
│
└── No upstream source (vscode-remote)
    → plugin: nil
    → Just set version in override-pull
```

### Common override-pull pattern (used by nearly all SDKs)

```bash
VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
craftctl set version="$VERSION"
# Then: curl, git clone, or nothing
```

### Plugin: nil — Version-only part

```yaml
parts:
  version:
    plugin: nil
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
```

Use when: SDK installs everything via hooks, or has no upstream binary.

### Plugin: dump — Pre-built binary

```yaml
parts:
  myapp:
    plugin: dump
    source: .
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
      curl -fLO "https://example.com/releases/v${VERSION}/myapp-linux-amd64.tar.gz"
      tar -xzf "myapp-linux-amd64.tar.gz" -C "$CRAFT_PART_SRC"
      rm "myapp-linux-amd64.tar.gz"
    organize:
      myapp: usr/bin/myapp
```

### Plugin: npm — Node.js CLI tool

```yaml
parts:
  mytool:
    plugin: npm
    source: .
    npm-include-node: true
    npm-node-version: 22.22.1
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
      curl -fLO "https://registry.npmjs.org/@scope/pkg/-/pkg-${VERSION}.tgz"
      tar -xzf "pkg-${VERSION}.tgz" --strip-components=1 -C "$CRAFT_PART_SRC"
      rm "pkg-${VERSION}.tgz"
```

### Multiple parts — Binary + service file

```yaml
parts:
  runtime:
    plugin: dump
    source: .
    override-pull: |
      # ... download binary
  services:
    plugin: dump
    source: services
    source-type: local
```

### Multiple parts — Binary + workshop-prompt

```yaml
parts:
  agent:
    plugin: npm
    # ... main tool
  workshop-prompt:
    plugin: dump
    source: workshop-prompt.md
    source-type: file
```

## Interface Layout Decision

### Mount plugs — persistent data

Use for any directory that should survive workshop updates:

| What to persist | Target pattern | Examples |
|---|---|---|
| Package cache | `~/.cache/<tool>` | uv, pnpm, yarn |
| Download cache | `~/.npm/_cacache` | npm |
| Config/credentials | `~/.<tool>` | copilot, claude, codex, rustup, cargo |
| Module/dep cache | `~/go/pkg/mod` | Go modules |
| Models | `~/.ollama/models` | Ollama |
| Build artifacts | `~/workspace` | ROS 2 colcon |
| VS Code server | `~/.vscode-server` | vscode-remote |
| Virtual env | `$SDK/venv` | jupyter |

```yaml
plugs:
  my-cache:
    interface: mount
    workshop-target: /home/workshop/.cache/mytool
```

Optional mount attributes: `mode`, `uid`, `gid`, `read-only`.

### GPU plug

```yaml
plugs:
  gpu:
    interface: gpu
```

Use when: ML inference, GPU-accelerated computation, graphics.

### Tunnel slot — expose a network service

```yaml
slots:
  my-server:
    interface: tunnel
    endpoint: 8080
```

Use when: SDK runs a daemon (Ollama, JupyterLab, etc.) that users access
from the host.

### Mount slot — share data with other SDKs

```yaml
slots:
  venv:
    interface: mount
    workshop-source: /home/workshop/my-venv
```

Use when: Other SDKs need to consume a resource this SDK produces (e.g., uv
providing a venv that jupyter consumes).

### Desktop and SSH plugs

```yaml
plugs:
  desktop:
    interface: desktop    # Wayland socket access
  ssh-agent:
    interface: ssh        # SSH agent forwarding (must be named ssh-agent)
```

## Systemd Service Pattern

When the SDK runs a long-lived daemon:

1. Create `services/<name>.service`:

```ini
[Unit]
Description=My Service
After=network.target

[Service]
ExecStart=/bin/bash -lc "myapp serve"
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

2. Add a dump part:

```yaml
parts:
  services:
    plugin: dump
    source: services
    source-type: local
```

3. Install in `hooks/setup-project`:

```bash
install -D --mode=644 --target-directory ~/.config/systemd/user "$SDK/<name>.service"
systemctl --user daemon-reload
systemctl --user enable --now <name>
```

## Version Track Decision

```
Does the upstream project have multiple supported major versions?
├── YES → Multiple tracks: branch per major (e.g., 20, 22, 24 for Node.js)
│         Branch pattern: "[0-9]+" or "[0-9]+.[0-9]+"
│         Renovate: baseBranchPatterns lists each, with allowedVersions per branch
│
└── NO → Single "latest" track
          Branch: "latest"
          Renovate: baseBranchPatterns: ["latest"], no allowedVersions needed
```
