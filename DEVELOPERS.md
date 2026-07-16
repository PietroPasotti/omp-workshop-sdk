# Developer guide

## Pipeline and branch model

See [ADR-0001](docs/adrs/0001-release-automation-pipeline.md) for the full
rationale and design of the branch-to-track/channel mapping, Renovate
automation, build/upload pipeline, and the ruleset that gates merges.

Summary: each `track/<N>` branch maps to store channel `<N>/edge`. Renovate
promotes minor/patch releases automatically; major-version rollovers are handled
by `bootstrap-major.yml` (see **Bootstrapping** below).

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

Major-track creation is fully automated. `bootstrap-major.yml` runs daily at
05:00 UTC from the default branch. When it detects that the latest upstream omp
major exceeds the current default-branch major it:

1. Creates `track/N` via the GitHub refs API (pointing at the current HEAD,
   which already has passing build checks — no ruleset bypass needed).
2. Opens a PR `setup/track-N → track/N` with VERSION and renovate.json updated
   for the new major, with auto-merge enabled.
3. Creates the `N` store track via `sdkcraft create-track omp --track N`.
4. Changes the GitHub default branch to `track/N`.
5. Polls for the PR to auto-merge (~15 min), then triggers `upload.yml` for
   the first `N/edge` release.

**Required secrets**: `SDKCRAFT_STORE_TOKEN` (store auth) and `ADMIN_TOKEN`
(fine-grained PAT with Administration:write — used for the default-branch
change; without it the workflow logs a warning and the caller must run
`gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch=track/N`).

**First Renovate PR on a new track**: GitHub may show `action_required` on the
`Build SDK` check for the first PR opened by an automated actor on the new base
branch. Click "Approve and run" once; subsequent PRs on that track auto-run.

### Manual recovery (if bootstrap fails mid-run)

The workflow is idempotent — re-running it after the branch exists exits early.
Individual steps, if missed, can be run manually:

```bash
# Create store track (if missed):
sdkcraft create-track omp --track N

# Change default branch (if ADMIN_TOKEN was absent):
gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch=track/N

# Trigger first upload (if setup PR merged but upload was not triggered):
gh workflow run upload.yml --ref track/N -f branch=track/N
```

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
- [ ] Actions secret `ADMIN_TOKEN` set to a fine-grained PAT with
      Administration:write on this repo. Used by `bootstrap-major.yml` to
      change the default branch automatically; without it that step emits a
      `::warning::` and requires a one-time manual command.
- [ ] Actions secret `SDKCRAFT_STORE_CREDENTIALS_STAGING` set. Without it,
      `snapshot` silently treats the belt as empty and uploads/promotes fail
      auth. Confirm staging is the intended publish target.
- [ ] Store track `latest` and the `latest/stable` guardrail exist. Per-major
      store tracks (`<N>`) are created automatically by `bootstrap-major.yml`.
- [ ] Repository ruleset on `refs/heads/track/*` requiring the `build / build`
      status check (verify: `gh api repos/<owner>/<repo>/rules/branches/track/<N>`).
- [ ] "Allow GitHub Actions to create and approve pull requests" enabled
      (Settings → Actions → General) so Renovate can auto-merge.
