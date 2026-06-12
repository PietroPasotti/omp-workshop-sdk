# Developer guide

## Pipeline and branch model

See [ADR-0001](docs/adrs/0001-release-automation-pipeline.md) for the full
rationale and design of the branch-to-track/channel mapping, Renovate
automation, build/upload pipeline, and the ruleset that gates merges.

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

3. Update branch references in `build.yml`, `upload.yml`, and `renovate.json`:
   ```bash
   # .github/workflows/build.yml   — pull_request branches: ["track/15"] → ["track/16"]
   # .github/workflows/upload.yml  — push branches: ["track/15"] → ["track/16"]
   #     (only the push trigger; the `track:` it uploads to is derived from VERSION)
   # renovate.json — baseBranchPatterns, matchBaseBranches: "track/15" → "track/16"
   #                 allowedVersions: "/^15\\./" → "/^16\\./"
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

6. The `track/16` branch is gated automatically by the existing repository
   ruleset (`build-sdk-checks`) on the `refs/heads/track/*` pattern; no
   per-branch configuration is needed.

## On-demand release / dry-run

`.github/workflows/release-ondemand.yml` (manual `workflow_dispatch`) exercises
the whole release path — snapshot → build → upload → promote — without waiting
for Renovate or a push to `track/<N>`. Two inputs:

- `mode`:
  - `release` (**default**) — builds, uploads the new revisions to `<N>/edge`,
    and cascades the promotion belt. **This mutates the (staging) store.**
  - `dry-run` — builds both platforms, prints the would-be
    `sdkcraft upload … --release <N>/edge` and `sdkcraft release …` commands,
    attaches the `.sdk` files as workflow artifacts, and writes nothing to the
    store. (The snapshot step still *reads* `sdkcraft revisions`.)
- `runner`: JSON array of runner labels. Default `["ubuntu-latest"]` runs on
  GitHub-hosted runners — an LXD **container** build that needs no KVM, so it
  works in a runner-less fork. Pass `["self-hosted","linux","jammy","x64","xlarge"]`
  to build on the production fleet.

```bash
# Build-only smoke test (no store writes), GitHub-hosted:
gh workflow run release-ondemand.yml -f mode=dry-run -f runner='["ubuntu-latest"]'

# Force a real release on the production fleet:
gh workflow run release-ondemand.yml -f mode=release \
  -f runner='["self-hosted","linux","jammy","x64","xlarge"]'
```

`workflow_dispatch` requires the workflow file to exist on the **default
branch** before it can be triggered. `tests/spread.yaml` (LXD `vm: true`, KVM)
is intentionally *not* run here — `sdkcraft pack` (containers) is the
GitHub-hosted-safe build; `sdkcraft test` is not.

## Provisioning checklist

For the automation to run green end-to-end, the production repository/org must
have all of the following (a runner-less fork satisfies only the last two, so
use the on-demand `dry-run` path there):

- [ ] Self-hosted runners labelled `self-hosted,linux,jammy,x64,xlarge` (used by
      the reusable `build.yml`/`upload.yml`), **or** override their `runs-on`.
      Without runners the PR `build` check and `upload.yml` queue indefinitely.
- [ ] Actions secret `SDKCRAFT_STORE_CREDENTIALS_STAGING` set. Without it,
      `snapshot` silently treats the belt as empty and uploads/promotes fail
      auth. Confirm staging is the intended publish target.
- [ ] Store tracks `<N>` and `latest`, plus the `latest/stable` guardrail,
      already exist (one-time operator action, outside this repo).
- [ ] Repository ruleset on `refs/heads/track/*` requiring the `build / build`
      status check (verify: `gh api repos/<owner>/<repo>/rules/branches/track/<N>`).
- [ ] "Allow GitHub Actions to create and approve pull requests" enabled
      (Settings → Actions → General) so Renovate can auto-merge.
