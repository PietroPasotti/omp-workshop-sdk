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

### 5. Branch protection enforces the gate

A single GitHub branch protection rule on the pattern `track/*` requires the
`build` status check to pass before merging. This rule covers every current and
future track branch automatically and is the mechanism that prevents Renovate
from auto-merging a broken build.

### 6. Major-version rollover is a manual operator action

When upstream releases a new major (e.g. `v16.0.0`):

1. `git checkout -b track/16 track/15`
2. Set `VERSION` to the first `16.x` release.
3. Update branch references in `build.yml`, `upload.yml`, and `renovate.json`
   (`track/15` → `track/16`; `allowedVersions` major digit).
4. Push and set `track/16` as the GitHub default branch.

Branch protection for `track/16` is covered automatically by the existing
`track/*` rule.

See `DEVELOPERS.md` for the full step-by-step commands.

## Consequences

**Positive:**

- Channel membership is statically determined by branch name; there is no
  ambiguity about where a build lands.
- Minor/patch releases ship automatically within ~24 hours of an upstream tag
  on weekdays, with no human involvement.
- `allowedVersions` in `renovate.json` makes it structurally impossible for
  Renovate to bridge a major-version boundary.
- The `track/*` branch protection rule requires no maintenance as new tracks
  are added.

**Negative / trade-offs:**

- Bootstrapping a new major track requires editing branch references in three
  files (`build.yml`, `upload.yml`, `renovate.json`). A future improvement
  could derive the major from the branch name at workflow runtime to eliminate
  this manual step.
- Renovate uses `GITHUB_TOKEN` for authentication. PRs it opens will not
  trigger other Actions workflows unless branch protection is configured with
  the `build` check set as required and Renovate is allowed to merge (i.e. the
  automerge mechanism operates through the GitHub API merge endpoint, not a
  push event). If the `build` check is not marked required, Renovate may
  auto-merge before CI runs.
- Renovate only runs Mon–Fri. A weekend upstream release will not be promoted
  until the following Monday morning UTC.
