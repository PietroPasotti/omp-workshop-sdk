# Build-Test-Iterate Workflow

How to develop, test, and iterate on an SDK locally before publishing.

## Prerequisites

- `sdkcraft` installed (requires LXD 6.3+)
- `workshop` CLI installed
- The SDK source directory with `sdkcraft.yaml`

## Quick Iteration Loop

```
┌─────────────────────────────────────────────┐
│  1. Edit sdkcraft.yaml, hooks, services     │
│  2. sdkcraft try                            │
│  3. Create/update test workshop.yaml        │
│  4. workshop launch (or workshop refresh)   │
│  5. workshop shell → verify behavior        │
│  6. workshop info → check health            │
│  7. Fix issues → go to step 1              │
└─────────────────────────────────────────────┘
```

## Step 1: Build and try locally

```bash
# From the SDK source directory:
sdkcraft try --verbose
```

This builds the SDK and copies it to Workshop's try area. The SDK becomes
available as `try-<name>` in workshop.yaml.

Useful flags:
- `--destructive-mode` — build directly on host (faster, no LXD)
- `--platform ubuntu@24.04:amd64` — target a specific platform
- `--build-for amd64` — target a specific architecture
- `--shell-after` — drop into the build environment after building
- `--debug` — drop into the build environment if build fails

## Step 2: Create a test workshop

```yaml
# test-workshop.yaml
name: test-myapp
base: ubuntu@24.04
sdks:
  - name: try-myapp     # "try-" prefix for locally tried SDKs
```

For SDKs with services/tunnels, add the system SDK with matching plugs:

```yaml
name: test-myapp
base: ubuntu@24.04
sdks:
  - name: system
    plugs:
      myapp-api:
        interface: tunnel
        endpoint: 127.0.0.1:8080
  - name: try-myapp
```

For SDKs with GPU needs:

```yaml
sdks:
  - name: try-myapp
    plugs:
      gpu: {}
```

## Step 3: Launch and verify

```bash
workshop launch --verbose

# Check SDK health
workshop info

# Shell in and test
workshop shell

# Inside the workshop:
mytool --version
# ... test functionality
```

## Step 4: Iterate & Debug issues

After making changes to sdkcraft.yaml or hooks:

```bash
# Rebuild and try
sdkcraft try

# Refresh the running workshop (re-runs hooks)
workshop refresh

# Or for a clean start:
workshop remove test-myapp
workshop launch

# Debugging errors in a workshop after a failed launch or refresh
# Stop the container when it had an error and debug it via exec or shell
workshop launch --wait-on-error
workshop refresh --wait-on-error

workshop shell

workshop launch --abort || workshop refresh --abort
```

## Step 5: Test hooks specifically

### Verify setup-base

```bash
workshop shell
# Check PATH, installed packages, /etc/profile.d/ files
echo $PATH
cat /etc/profile.d/mytool.sh
```

### Verify setup-project

```bash
workshop shell
# Check user-level config, services, venvs
systemctl --user status myservice
ls ~/my-config-dir/
```

### Verify check-health

```bash
workshop info
# Look for the health status line
```

### Verify save-state / restore-state

```bash
# 1. Make a change inside the workshop
workshop shell
# (modify some setting)

# 2. Refresh to trigger save-state → restore-state
workshop refresh

# 3. Verify the change survived
workshop shell
# (check the setting is preserved)
```

## Step 6: Automated testing with spread

```bash
# Run all tests
sdkcraft test

# List available test jobs
sdkcraft test --list

# Run a specific test
sdkcraft test tests/my-suite/
```

`sdkcraft test` automatically:
- Packs SDKs for all matching platforms
- Copies them via `sdkcraft try`
- Installs Workshop in the test environment
- Runs spread test suites

## Full build (for CI verification)

```bash
# Full build producing .sdk artifact
sdkcraft build
sdkcraft stage
sdkcraft prime
sdkcraft pack

# The .sdk file will be in the current directory
ls *.sdk
```

## Debugging build failures

```bash
# Shell into build environment on failure
sdkcraft build --debug

# Shell into build environment after success
sdkcraft build --shell-after

# Shell into environment instead of building
sdkcraft build --shell
```

## Common issues

| Problem | Solution |
|---|---|
| `sdkcraft try` fails to find VERSION | Ensure VERSION file exists in project root |
| Hook not running | Check hook file is executable (`chmod +x hooks/setup-base`) |
| SDK not found in workshop | Use `try-<name>` prefix in workshop.yaml |
| Health check fails | `workshop shell` and manually run the check-health script |
| Mount not persisting | Verify plug name and workshop-target path match |
