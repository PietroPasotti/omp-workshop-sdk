# Hooks Reference

All hooks live in the `hooks/` directory next to `sdkcraft.yaml`. They are
shell scripts run by Workshop at specific lifecycle points.

## Available Hooks

| Hook | When | Runs as | Purpose |
|---|---|---|---|
| `setup-base` | Launch and refresh | root | System-wide config: PATH, apt packages, symlinks |
| `setup-project` | After setup-base, interfaces connected | workshop user | Project-specific init: services, venv, deps |
| `check-health` | After setup-project | root | Report SDK health via `workshopctl set-health` |
| `save-state` | Before refresh | workshop user | Persist custom state to `$SDK_STATE_DIR` |
| `restore-state` | After refresh | workshop user | Restore state from `$SDK_STATE_DIR` |

## Environment Variables in Hooks

- `$SDK` — absolute path to the SDK's install directory (read-only)
- `$SDK_STATE_DIR` — writable directory for save-state/restore-state
- `$CRAFT_PLATFORM` — platform string (e.g., `ubuntu@24.04:amd64`)

## Hook: setup-base

Runs as root. System-wide environment setup.

### Pattern: Add tool to PATH

```bash
#!/usr/bin/bash
cat <<EOF >/etc/profile.d/mytool.sh
export PATH="${SDK}/bin:\$PATH"
EOF
```

### Pattern: Install apt packages

```bash
#!/usr/bin/bash
apt-get update
eatmydata apt-get install package1 package2
```

Use `eatmydata` to skip fsync during install (the workshop image provides it).
Do not pass `-y` or `--no-install-recommends` — the workshop image configures
those defaults via apt configuration.

### Pattern: Generate shell completions

```bash
#!/usr/bin/bash
"$SDK"/bin/mytool completion bash > /etc/bash_completion.d/mytool.sh
```

### Pattern: Configure SSH (vscode-remote)

```bash
#!/usr/bin/bash
USER="workshop"
sed -i 's/^#\?\(PasswordAuthentication\) .*/\1 yes/' /etc/ssh/sshd_config
sed -i 's/^#\?\(PermitEmptyPasswords\) .*/\1 yes/' /etc/ssh/sshd_config
passwd -d "$USER"
service ssh restart || systemctl restart ssh
```

### Pattern: Create system alternatives (uv wrapping pip)

```bash
#!/usr/bin/bash
mkdir -p /usr/local/libexec/alternatives
cat << 'EOF' > /usr/local/libexec/alternatives/uv-pip
#!/bin/bash
exec uv pip "$@"
EOF
chmod +x /usr/local/libexec/alternatives/uv-pip
update-alternatives --install /usr/bin/pip pip /usr/local/libexec/alternatives/uv-pip 50
```

## Hook: setup-project

Runs as the workshop user. Interfaces are connected, /project is mounted.

### Pattern: Start a systemd user service

```bash
#!/usr/bin/bash
install -D --mode=644 --target-directory ~/.config/systemd/user "$SDK/myservice.service"
systemctl --user daemon-reload
systemctl --user enable --now myservice
```

### Pattern: Create a virtual environment

```bash
#!/usr/bin/bash
if [ ! -d "$SDK/venv/bin" ]; then
    python3 -m venv "$SDK/venv"
    "$SDK/venv/bin/pip" install --upgrade pip
    "$SDK/venv/bin/pip" install jupyterlab==$(cat "$SDK/VERSION")
fi
```

### Pattern: Set user environment variables

```bash
#!/usr/bin/bash
cat <<EOF >> ~/.profile
export UV_LINK_MODE=copy
EOF
```

### Pattern: Copy config file (idempotent)

```bash
#!/usr/bin/bash
mkdir -p /home/workshop/.myconfig
if [[ ! -f "/home/workshop/.myconfig/settings.md" ]]; then
    cp "${SDK}/default-settings.md" "/home/workshop/.myconfig/settings.md"
fi
```

### Pattern: Detect GPU type

```bash
#!/usr/bin/bash
GPU_TYPE="none"
if command -v lspci >/dev/null 2>&1; then
    if lspci | grep -i 'NVIDIA' >/dev/null 2>&1; then
        GPU_TYPE="nvidia"
    elif lspci | grep -i 'AMD/ATI' >/dev/null 2>&1; then
        GPU_TYPE="amd"
    fi
fi
```

## Hook: check-health

Reports SDK status. Must call `workshopctl set-health`.

### Health states

- `workshopctl set-health okay` — SDK is fully operational
- `workshopctl set-health waiting "message"` — still starting (retry)
- `workshopctl set-health error "message"` — failed

### Pattern: Simple binary check

```bash
#!/usr/bin/bash
if ! sudo -u workshop --login mytool --version >/dev/null 2>&1; then
    workshopctl set-health error "mytool not available on PATH"
    exit 0
fi
workshopctl set-health okay
```

### Pattern: Service check with output

```bash
#!/usr/bin/bash
if ! output=$(sudo -u workshop --login myservice list 2>&1); then
    workshopctl set-health waiting "$output"
    exit 0
fi
workshopctl set-health okay
```

### Pattern: SSH service check (vscode-remote)

```bash
#!/usr/bin/bash
if ! (systemctl --wait is-active --quiet ssh.socket \
   || systemctl --wait is-active --quiet ssh.service); then
    workshopctl set-health error "SSH service/socket not running"
    exit 1
fi
ip=$(hostname -I | awk '{print $1}')
echo -n "VS Code → Open Remote Window → Connect to host → workshop@$ip"
workshopctl set-health okay
```

## Hook: save-state / restore-state

Used for preserving user-modified settings across refreshes.

### Pattern: Save/restore environment variables (go-sdk)

**save-state:**
```bash
#!/usr/bin/bash
CHANGED=$(sudo -u workshop --login go env -changed)
if [ -n "$CHANGED" ]; then
    echo "$CHANGED" > "$SDK_STATE_DIR/env-vars"
fi
```

**restore-state:**
```bash
#!/usr/bin/bash
if [ -f "$SDK_STATE_DIR/env-vars" ]; then
    while IFS='=' read -r key value; do
        sudo -u workshop --login go env -w "$key=$value"
    done < "$SDK_STATE_DIR/env-vars"
fi
```

## Which Hooks to Use — Decision Guide

```
Does SDK need system-wide setup (PATH, apt)?
└── YES → setup-base (always needed)

Does SDK need project-specific init or services?
└── YES → setup-project

Should we verify the SDK works?
└── YES → check-health (strongly recommended)

Does the SDK have user-modifiable state to preserve?
└── YES → save-state + restore-state
```

Most SDKs need: **setup-base** + **check-health** at minimum.
Add **setup-project** if services, venvs, or project-dependent config is needed.
Add **save-state** / **restore-state** only for mutable environment state.
