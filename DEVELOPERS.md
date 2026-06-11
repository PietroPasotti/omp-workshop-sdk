# Developer guide

## Pipeline and branch model

See [ADR-0001](docs/adrs/0001-release-automation-pipeline.md) for the full
rationale and design of the branch-to-track/channel mapping, Renovate
automation, build/upload pipeline, and branch protection requirements.

Summary: each `track/<N>` branch maps to store channel `<N>/edge`. Renovate
promotes minor/patch releases automatically; a major-version rollover is a
deliberate operator action (see **Bootstrapping** below).

On every push to a `track/<N>` branch the upload pipeline runs three jobs:

1. **snapshot** — records which revisions are currently in `<N>/edge`,
   `<N>/beta`, and `<N>/candidate` (pre-upload state). The store track is
   derived from the major in `VERSION` (`15.x.y → 15`), not from the branch
   name.
2. **build-and-upload** — builds both platforms and releases the new revisions
   to `<N>/edge`.
3. **promote** — cascades the pre-upload revisions one risk level down:
   `<N>/candidate → <N>/stable + latest/stable`, `<N>/beta → <N>/candidate`,
   `<N>/edge → <N>/beta`. Empty tiers are no-ops.

The promotion script is `.github/scripts/promote-pipeline.sh`; run its test
harness with `bash .github/scripts/promote-pipeline.test.sh`.

## Local development

Always work from a `track/*` branch:

```bash
git checkout track/15
sdkcraft try --verbose
# edit workshop.yaml to reference the try-built SDK
workshop launch
workshop shell
omp --version
workshop info   # runs check-health
```

## Bootstrapping a new major version

When upstream releases `v16.0.0` (or any `16.x`):

1. Create the new version branch from the current default:
   ```bash
   git checkout -b track/16 track/15
   ```

2. Set `VERSION` to the first 16.x release:
   ```bash
   echo "16.0.0" > VERSION
   ```

3. Update branch references in `build.yml` and `renovate.json`:
   ```bash
   # .github/workflows/build.yml  — branches: ["track/15"] → ["track/16"]
   # renovate.json — baseBranchPatterns, matchBaseBranches: "track/15" → "track/16"
   #                 allowedVersions: "/^15\\./" → "/^16\\./"
   # Note: upload.yml needs no branch-reference edit — track is derived from VERSION.
   ```

4. Commit and push:
   ```bash
   git add -A && git commit -m "chore: configure 16/edge track"
   git push -u origin track/16
   ```

5. Roll the GitHub default branch:
   ```bash
   gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch='track/16'
   ```

6. Branch protection for `track/16` is covered automatically by the existing
   `track/*` rule; no action needed.
