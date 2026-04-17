# Onboarding Reference

Steps to bring an SDK repo up to the established versioning, CI, and Renovate
patterns. Based on SDK_ONBOARDING_PLAN.md.

## Prerequisites

Before onboarding, determine:
- **Version track**: `latest` (single), or major/major.minor branches
- **Datasource**: How Renovate discovers new versions (npm, github-releases,
  pypi, golang-version, node-version, etc.)
- **Dep name**: Upstream package identifier (e.g., `@github/copilot`,
  `microsoft/vscode`, `node`, `jupyterlab`)

## Step 1: Create VERSION file

Single line with the current version number:

```
1.0.14
```

## Step 2: Update sdkcraft.yaml

Replace hardcoded `version:` with `adopt-info`:

```yaml
# Before:
name: myapp
version: "1.0"

# After:
name: myapp
adopt-info: myapp   # must match a part name
```

Ensure the matching part reads VERSION:

```yaml
parts:
  myapp:
    override-pull: |
      VERSION=$(cat "$CRAFT_PROJECT_DIR/VERSION")
      craftctl set version="$VERSION"
      # ... rest of pull logic
```

## Step 3: Configure renovate.json

### Single latest track

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "enabledManagers": ["custom.regex"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^VERSION$/"],
      "matchStrings": ["(?<currentValue>[0-9.]+)"],
      "depNameTemplate": "UPSTREAM_NAME",
      "datasourceTemplate": "DATASOURCE",
      "versioningTemplate": "semver"
    }
  ],
  "baseBranchPatterns": ["latest"],
  "packageRules": [
    {
      "matchPackageNames": ["UPSTREAM_NAME"],
      "matchBaseBranches": ["latest"]
    }
  ]
}
```

### Multiple version tracks

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "enabledManagers": ["custom.regex"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^VERSION$/"],
      "matchStrings": ["(?<currentValue>[0-9.]+)"],
      "depNameTemplate": "node",
      "datasourceTemplate": "node-version",
      "versioningTemplate": "semver"
    }
  ],
  "baseBranchPatterns": ["20", "22", "24"],
  "packageRules": [
    {
      "matchPackageNames": ["node"],
      "baseBranchPatterns": ["20"],
      "allowedVersions": "/^20\\./"
    },
    {
      "matchPackageNames": ["node"],
      "baseBranchPatterns": ["22"],
      "allowedVersions": "/^22\\./"
    },
    {
      "matchPackageNames": ["node"],
      "baseBranchPatterns": ["24"],
      "allowedVersions": "/^24\\./"
    }
  ]
}
```

### Common datasource templates

| Software type | datasourceTemplate | depNameTemplate example |
|---|---|---|
| npm package | `npm` | `@github/copilot` |
| GitHub releases | `github-releases` | `microsoft/vscode` |
| PyPI package | `pypi` | `jupyterlab` |
| Node.js runtime | `node-version` | `node` |
| Go runtime | `golang-version` | `go` |
| Rust toolchain | `github-releases` | `rust-lang/rustup` |

Add `extractVersionTemplate` if upstream tags have a prefix:
```json
"extractVersionTemplate": "^v(?<version>.*)$"
```

## Step 4: Update GitHub Actions workflows

### build.yml

```yaml
name: Build SDK

on:
  pull_request:
    branches:
      - latest              # or "[0-9]+" or "[0-9]+.[0-9]+"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true

jobs:
  build:
    uses: canonical/sdkcraft-actions/.github/workflows/build.yml@main
```

### upload.yml — single-base SDK

```yaml
name: Build and Upload SDK

on:
  push:
    branches:
      - latest
  workflow_dispatch:
    inputs:
      branch:
        description: "Branch name (e.g., latest)"
        required: true
        type: string

concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true

jobs:
  build-and-upload:
    uses: canonical/sdkcraft-actions/.github/workflows/upload.yml@main
    with:
      platforms: '["amd64"]'
      risk: "stable"
    secrets:
      SDKCRAFT_STORE_CREDENTIALS: ${{ secrets.SDKCRAFT_STORE_CREDENTIALS_STAGING }}
```

### upload.yml — multi-base SDK

```yaml
jobs:
  build-and-upload:
    uses: canonical/sdkcraft-actions/.github/workflows/upload.yml@main
    with:
      platforms: '["ubuntu@22.04:amd64","ubuntu@24.04:amd64"]'
      platform-flag: "--platform"
      risk: "stable"
    secrets:
      SDKCRAFT_STORE_CREDENTIALS: ${{ secrets.SDKCRAFT_STORE_CREDENTIALS_STAGING }}
```

### Branch pattern reference

| Track style | Branch pattern | Examples |
|---|---|---|
| Single latest | `latest` | copilot, jupyter, vscode-remote |
| Major only | `"[0-9]+"` | node (20, 22, 24), rust |
| Major.minor | `"[0-9]+.[0-9]+"` | go (1.24), uv (0.7) |

## Step 5: Git workflow

Execute these commands in order:

```bash
# 1. Stage and commit all onboarding changes
git add -A
git commit -m "Add VERSION file, renovate config, and version-based workflows"

# 2. Remove VERSION from main (main is the template)
git rm VERSION
git commit -m "Remove VERSION from main"

# 3. Create version branch pointing at the commit WITH VERSION
git checkout -b latest HEAD~1    # or the track name

# 4. Remove Renovate workflows from version branch
git rm .github/workflows/renovate.yml .github/workflows/renovate-check.yml
git commit -m "Remove Renovate workflows from version branch"

# 5. Return to main
git checkout main

# 6. Push both branches
git push origin main
git push origin latest
```

### Why this structure?

- **main**: Template branch. Has renovate.json + Renovate workflows. No VERSION.
  Renovate runs from main and targets version branches.
- **version branches** (latest, 20, 1.24, etc.): Has VERSION file. Has build +
  upload workflows. No Renovate workflows (those only run from main).

### Multiple version branches

For SDKs with multiple tracks, create one branch per track:

```bash
# After the main commit with VERSION:
git checkout -b 20 HEAD~1
# set VERSION to 20.x.x
git rm .github/workflows/renovate.yml .github/workflows/renovate-check.yml
git commit -m "Remove Renovate workflows from version branch"

git checkout main
git checkout -b 22 HEAD~1
# set VERSION to 22.x.x
git rm .github/workflows/renovate.yml .github/workflows/renovate-check.yml
git commit -m "Remove Renovate workflows from version branch"
```
