# ADR-0001: Release automation pipeline and branch-to-track/channel mapping

Date: 2026-06-11
Status: Accepted

## Context

`omp` (`oh-my-pi`) follows a major-version release cadence where each upstream
major (`15.x`, `16.x`, …) is a long-lived, independently maintained line. The
Workshop store uses a `<major>/edge` channel model, so SDK consumers who pin to
`15/edge` must never receive a `16.x` binary automatically.

The goals this design must satisfy:

- Minor and patch releases of the active major land in the store with no human
  intervention.
- A major-version boundary is never crossed without a deliberate operator action
  (branch creation + default-branch rollover).
- The store channel a build is released to is unambiguously determined by the
  source branch — no runtime switch or environment variable chooses the channel.
- Local iteration (`sdkcraft try`) works without special setup.

## Decision

### 1. One `track/<N>` branch per upstream major; no `main`

Each long-lived branch corresponds to exactly one upstream major version and one
store track:

| Branch      | Store channel | Upstream version range |
|-------------|---------------|------------------------|
| `track/15`  | `15/edge`     | `15.x.y`               |
| `track/16`  | `16/edge`     | `16.x.y` (future)      |
| `track/<N>` | `<N>/edge`    | `<N>.x.y` (future)     |

The GitHub default branch always points to the **currently active** track.
There is no `main`; `git clone` lands directly on the active track.

### 2. `VERSION` file as the single source of truth

A plain-text `VERSION` file (e.g. `15.11.0`) at the repo root is the only
place where the upstream version is recorded. `sdkcraft.yaml` reads it at build
time to derive both the binary download URL and the SDK version field. No
version appears in workflow files or elsewhere.

### 3. Renovate for automated minor/patch promotion

Renovate is configured (`renovate.json`) on the default branch with a custom
regex manager that treats `VERSION` as a dependency on the
`github-releases` datasource for `can1357/oh-my-pi`.

Critical constraints in `renovate.json`:

- `baseBranchPatterns: ["track/<N>"]` — Renovate only scans the active track
  branch, not every branch in the repo.
- `allowedVersions: "/^<N>\\./"`  — Renovate refuses to propose a version whose
  major differs from the track, making cross-major bumps impossible through
  automation.
- `automerge: true` / `automergeType: "pr"` — once the `build` status check
  passes, Renovate merges automatically; no human approval needed for
  minor/patch updates.

Renovate runs on a scheduled workflow (`renovate.yml`) on weekdays at 04:00 UTC.

### 4. CI/CD pipeline: build check → automerge → upload

```
upstream releases v<N>.x.y on GitHub
        │
        ▼
renovate.yml  (Mon–Fri 04:00 UTC, runs on default branch)
  detects VERSION is behind latest <N>.x.y
  opens PR: bump VERSION to <N>.x.y
        │
        ▼
build.yml  (required check — triggers on PRs targeting track/<N>)
  canonical/sdkcraft-actions reusable workflow
  runs `sdkcraft build` for ubuntu@22.04:amd64 and ubuntu@24.04:amd64
        │  passes
        ▼
Renovate auto-merges the PR
        │
        ▼
upload.yml  (triggers on push to track/<N>)
  canonical/sdkcraft-actions reusable workflow
  builds + uploads to the Workshop store
  risk: edge, channel: <N>   ← derived purely from branch name
```

The channel is never parameterised at runtime; it is encoded in `upload.yml`
via the `risk: edge` field and the branch trigger. The major component of the
channel is implicit in *which* `track/*` branch is the default.

### 5. A repository ruleset enforces the gate

A single GitHub repository ruleset (`build-sdk-checks`, `target: branch`,
`enforcement: active`) on the ref pattern `refs/heads/track/*` requires the
`build / build` status check to pass before a matching branch can be updated.
The required-check **context** must be the check-run name produced by the
reusable workflow — `build / build` (the caller job id `build` joined to the
reusable workflow's `build` job), **not** the workflow `name:` (`Build SDK`).
The same ruleset also blocks branch deletion and non-fast-forward (force)
pushes. The `refs/heads/track/*` pattern covers every current and future track
branch automatically and is the mechanism that prevents Renovate from
auto-merging a broken build.

> Note: the pattern must be `refs/heads/track/*` (with the trailing `*`). A
> bare `refs/heads/track/` matches no branch, leaving the track unprotected.
> Verify with `gh api repos/<owner>/<repo>/rules/branches/track/<N>` — it must
> list the `deletion`, `non_fast_forward`, and `required_status_checks` rules.

### 6. Major-version rollover is automated

`bootstrap-major.yml` runs daily at 05:00 UTC from the default branch and on
`workflow_dispatch`. It queries the upstream GitHub releases, compares the
highest published major against the default-branch track number, and — when a
gap is found — performs the full rollover unattended:

1. Creates `track/N` via the Git Refs API, pointing at the current HEAD commit
   (already verified by CI). No ruleset disable/re-enable is required.
2. Pushes VERSION and renovate.json changes to `setup/track-N` (unprotected)
   and opens a PR to `track/N` with auto-merge enabled.
3. Creates the store track via `sdkcraft create-track omp --track N`.
4. Changes the GitHub default branch to `track/N` (requires the `ADMIN_TOKEN`
   secret; if absent the step warns and the caller does it manually).
5. Polls for the PR to auto-merge, then triggers the first `upload.yml` run.

`build.yml` and `upload.yml` use `branches: ["track/*"]` so they apply to every
current and future track branch with no per-track edits.

The workflow is idempotent: if `track/N` already exists it exits cleanly.

## Amendment: release-promotion conveyor (2026-06-11)

Status: Accepted

### Context

The original pipeline releases every new revision only to `<N>/edge`. The store
supports a stable promotion ladder (`edge → beta → candidate → stable`), but no
automation advanced revisions through it. Additionally, the reusable upload
workflow (`canonical/sdkcraft-actions`) derives the store track from
`GITHUB_REF` (`track/15/edge`) when no `track:` input is supplied; the channel
validator rejects this string because `15` is not a valid risk name.

### Decision

**Fix the track derivation:** derive the track from the major component of
`VERSION` (`cut -d. -f1 VERSION`) and pass it explicitly as `track:` to the
upload job. `VERSION` is already the single source of truth; no new hardcoded
value is introduced.

**Add a promotion conveyor:** restructure `upload.yml` into three sequential
jobs:

```
snapshot        — record which revisions sit in edge/beta/candidate BEFORE upload
build-and-upload — build + release two new revisions to <N>/edge (existing logic)
promote         — shift the pre-upload revisions one tier down the belt:
                    candidate → <N>/stable AND latest/stable
                    beta      → <N>/candidate
                    edge      → <N>/beta
```

The conveyor logic lives in `.github/scripts/promote-pipeline.sh` (injectable
`$SDKCRAFT` for testing) with subcommands `snapshot`, `promote`, and
`channel-revs` (pure parser for test isolation).

Values flow from `snapshot` to `promote` via GitHub Actions job outputs
referenced through env vars (not inline `${{ }}` expressions) to prevent shell
injection. The existing `concurrency` group serialises pipelines per branch, so
the read-then-shift sequence is race-free within a track.

### Channel parsing

`sdkcraft revisions` emits a whitespace-aligned table with columns
`CHANNEL REVISION ARCHITECTURE UPLOADED`, where `CHANNEL` may be a
comma-joined list (no spaces) when a revision appears in multiple channels
(e.g. `15/candidate,15/stable`). The parser:

- skips the header and any craft-cli noise by requiring column 2 to be an
  integer (`$2 ~ /^[0-9]+$/`);
- splits the channel cell on `,` and compares each token exactly to the
  target — `15/edge` does not match `115/edge` or `5/edge`.

`sdkcraft revisions` failure is retried (3 attempts) and then treated as an
empty belt, so the first-ever release and transient outages are no-ops rather
than corruption events.

### Edge cases

- **Empty belt tiers**: empty revision lists are no-ops for that tier.
- **Two revisions per channel** (one per base): both are promoted.
- **Re-running `promote`**: idempotent — uses the captured snapshot.
- **Pre-existing wrongly-named revisions** (e.g. uploaded under `track/15/edge`
  before this fix): not found under `15/edge`, so not promoted. The belt
  rebuilds cleanly from the next real release.

### Consequences

**Positive:**

- Store channels `<N>/beta`, `<N>/candidate`, `<N>/stable`, and `latest/stable`
  are populated automatically without human intervention.
- The track derivation bug is fixed; the store will no longer reject the channel
  name on upload.
- The promotion script is fully testable locally with a mock `sdkcraft` binary.

**Negative / trade-offs:**

- Each release now requires three jobs instead of one; end-to-end wall time
  increases by one extra `snap install sdkcraft` + store API round-trip.
- `latest/stable` reflects whichever active track finished last if multiple
  tracks release concurrently — acceptable because Renovate pushes only to the
  single default branch.
- Store tracks (`<N>` and `latest`) and the `latest/stable` guardrail must exist
  in the store before the first promotion; this is a one-time operator action
  outside this repository.

## Consequences

**Positive:**

- Channel membership is statically determined by branch name; there is no
  ambiguity about where a build lands.
- Minor/patch releases ship automatically within ~24 hours of an upstream tag
  on weekdays, with no human involvement.
- `allowedVersions` in `renovate.json` makes it structurally impossible for
  Renovate to bridge a major-version boundary.
- The `refs/heads/track/*` ruleset requires no maintenance as new tracks
  are added.

**Negative / trade-offs:**

- Bootstrapping a new major track is automated by `bootstrap-major.yml`
  (see Amendment: automated major-track bootstrap, below). The `build.yml`
  and `upload.yml` branch filters now use `track/*` so no per-track file
  edits are needed at rollover time.
- Renovate uses `GITHUB_TOKEN` for authentication. PRs it opens will not
  trigger other Actions workflows unless the ruleset is configured with the
  `build / build` check set as required and Renovate is allowed to merge (i.e.
  the automerge mechanism operates through the GitHub API merge endpoint, not a
  push event). If the `build / build` check is not marked required, Renovate
  may auto-merge before CI runs.
- Renovate only runs Mon–Fri. A weekend upstream release will not be promoted
  until the following Monday morning UTC.

## Amendment: automated major-track bootstrap (2026-07-16)

Status: Accepted

### Context

The original design treated major-version rollovers as deliberate manual
operator actions (ADR section 6). In practice this created a window where
upstream published a new major but no SDK track existed. A scheduled workflow
that detects and closes this gap automatically was added.

### Decision

Add `bootstrap-major.yml` (daily 05:00 UTC, `workflow_dispatch`). When the
highest upstream major exceeds the current default-branch major it runs the
full rollover unattended (branch creation, store track, default-branch change,
first upload). See section 6 above for the step-by-step.

Change `build.yml` and `upload.yml` branch patterns from the hard-coded
`track/<N>` to `track/*`. This eliminates the need to edit either file at
rollover time and ensures the build check and upload trigger work on new track
branches immediately.

### Consequences

**Positive:**

- New major tracks go live without human involvement (except a one-time
  "Approve and run" click for the first Renovate PR on the new track).
- No more per-track edits to `build.yml` or `upload.yml`.

**Negative / trade-offs:**

- The `build` check now fires for PRs targeting any `track/*` branch,
  including legacy branches. In practice only the active track receives PRs.
- The `ADMIN_TOKEN` secret (fine-grained PAT with Administration:write) is
  required for the automatic default-branch change; without it that step
  degrades to a warning rather than a hard failure.
- `GITHUB_TOKEN`-initiated merges do not trigger further workflows (GitHub
  recursion protection), so the bootstrap polls for the PR merge and then
  fires `upload.yml` explicitly.
