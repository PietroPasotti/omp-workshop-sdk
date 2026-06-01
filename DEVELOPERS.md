# Developer guide

## Branch model

| Branch | Purpose | Contains |
|--------|---------|---------|
| `track/<N>` | Buildable version branch for major `N` | `VERSION`, all workflows including Renovate |

There is no long-lived `main`. The **default branch** is always the current active track
(`track/15` right now). `git clone` and `sdkcraft pack` / `sdkcraft try` land here directly.
When the next upstream major ships, roll the default branch forward to the new `track/*`
(see below).

## Release automation

```
upstream releases v15.x.y on GitHub
         │
         ▼
Renovate (scheduled on the default branch, Mon–Fri 04:00 UTC)
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
Key config points:
- `renovate.json` on the default branch (`track/15`) sets `baseBranchPatterns: ["track/15"]`
  and `allowedVersions: "/^15\\./"`  — Renovate targets only the right branch and never
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

3. Update the branch references in the CI workflows and `renovate.json`:
   ```bash
   # .github/workflows/build.yml  — branches: ["track/15"] → ["track/16"]
   # .github/workflows/upload.yml — branches: ["track/15"] → ["track/16"]
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

6. Branch protection for `track/16` is covered automatically by the existing
   `track/*` rule; no action needed.
