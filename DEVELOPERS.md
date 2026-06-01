# Developer guide

## Branch model

| Branch | Purpose | Contains |
|--------|---------|---------|
| `main` | Template / Renovate host | SDK source, `renovate.json`, Renovate workflows — no `VERSION` |
| `track/<N>` | Buildable version branch for major `N` | `VERSION`, `build.yml`, `upload.yml` — no Renovate workflows |

`track/15` is currently the **default branch** — what `sdkcraft pack` / `sdkcraft try` and
casual `git clone` users land on. When the next upstream major ships, roll the default branch
forward to `track/16` (see below).

`main` is never built directly. It exists so Renovate has a stable home for its workflows
and config, independent of which `track/*` branch is current.

## Release automation

```
upstream releases v15.x.y on GitHub
         │
         ▼
Renovate (scheduled on main, Mon–Fri 04:00 UTC)
  reads VERSION on track/15, detects newer 15.x release
  opens PR: VERSION 15.7.3 → 15.x.y
         │
         ▼
build.yml  (PR check — triggers on PRs targeting track/15)
  runs sdkcraft build inside the sdkcraft-actions reusable workflow
         │  passes → Renovate auto-merges (automerge: true)
         ▼
upload.yml  (push to track/15)
  builds + uploads to the Workshop store at risk: edge, channel: 15
```

Key config points:
- `renovate.json` on `main` sets `baseBranchPatterns: ["track/15"]` and
  `allowedVersions: "/^15\\./"`  — Renovate targets only the right branch and never
  proposes a major-version bump across the track boundary.
- `automerge: true` / `automergeType: "pr"` — Renovate merges automatically once
  all required checks pass. **Requires branch protection on `track/*` with the `build`
  status check set as required** (see below), otherwise Renovate may merge before CI runs.

## Branch protection

In GitHub Settings → Branches, there is one rule with pattern `track/*`:

- Require status checks to pass before merging → add `build`
- (The check name won't appear in the autocomplete until the workflow has run at least
  once. Either type `build` manually, or open a throwaway PR against `track/15` first.)

This single rule covers every current and future `track/*` branch automatically.

## Local development

Always work from the version branch, not `main`:

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

1. Create the new version branch from `main`:
   ```bash
   git checkout -b track/16 main
   ```

2. Remove Renovate workflows (they live on `main` only):
   ```bash
   git rm .github/workflows/renovate.yml .github/workflows/renovate-check.yml
   ```

3. Set `VERSION` to the first 16.x release:
   ```bash
   echo "16.0.0" > VERSION
   ```

4. Update the branch references in both CI workflows:
   ```bash
   # .github/workflows/build.yml  — branches: ["track/15"] → ["track/16"]
   # .github/workflows/upload.yml — branches: ["track/15"] → ["track/16"]
   ```

5. Commit and push:
   ```bash
   git add -A && git commit -m "chore: configure 16/edge track"
   git push -u origin track/16
   ```

6. On `main`, extend `renovate.json` — add `track/16` to `baseBranchPatterns` and
   add a new package rule mirroring the `track/15` entry with `allowedVersions: "/^16\\./"`
   targeting `matchBaseBranches: ["track/16"]`. Commit and push `main`.

7. Roll the GitHub default branch from `track/15` to `track/16`:
   ```bash
   gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch='track/16'
   ```

8. Set branch protection for `track/16` — covered automatically by the existing
   `track/*` rule; no action needed.
