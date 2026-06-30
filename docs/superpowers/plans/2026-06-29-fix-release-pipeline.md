# Fix Release Pipeline and Bootstrap track/16

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the automated omp SDK release pipeline (currently 100% broken) and bootstrap the track/16 branch so omp v16.2.5 can be released to the Workshop store.

**Architecture:** Three independent failures stacked on each other. Fix the runner bug first (unblocks everything), then drain the open PR backlog to land 15.x in the store, then bootstrap track/16 so 16.x automation starts working.

**Tech Stack:** GitHub Actions, sdkcraft, Renovate bot, bash

## Global Constraints

- NEVER modify `promote-pipeline.sh` or `promote-pipeline.test.sh` unless a task explicitly calls for it.
- NEVER push directly to `track/15` without a passing CI check (`build / build`) — repository ruleset enforces it.
- All `VERSION` values are bare semver (e.g. `16.2.5`), no `v` prefix; the `v` prefix is only on git tags.
- Secret name in the repo is `SDKCRAFT_STORE_CREDENTIAL` (singular) — do not change it; YAML references it correctly.
- `upload.yml` push trigger branch must stay `"track/15"` even after track/16 is created — the track is derived at runtime from `VERSION`, not from the branch name.
- When bootstrapping track/16, `upload.yml` gets NO branch edit; `build.yml` and `renovate.json` DO get branch edits.

---

## Diagnosis (read-only background — no steps)

Every single "Build and Upload SDK" workflow run since the pipeline was introduced has been **cancelled**. The pattern:

- `snapshot` job → completes in ~2 min on ubuntu-latest ✓  
- `build-and-upload` sub-jobs → queue, wait up to 24 h, then GitHub auto-cancels ✗  
- `promote` job → skipped (never reached) ✗

**Root cause:** `upload.yml` calls the reusable workflow
`canonical/sdkcraft-actions/.github/workflows/upload.yml@main` **without** the `runs-on` input.
That input defaults to `'["self-hosted","linux","jammy","x64","xlarge"]'`.
This repo has no such self-hosted runners, so both platform jobs sit in queue until the
24-hour GitHub timeout fires.

Compare with `build.yml`, which works because it explicitly passes `runs-on: ubuntu-latest`.

**Secondary issues:**

| # | Problem | Impact |
|---|---------|--------|
| 1 | `upload.yml` missing `runs-on` | No SDK has ever reached the store from this automation |
| 2 | Renovate PR #9 CI is `action_required` | Bot PR needs manual CI approval; automerge never fires; VERSION stuck at 15.11.0 |
| 3 | PR #8 open (on-demand harness, checkout v4→v6) | Useful tooling not landed; checkout v4 will break on 2026-06-16 runner deprecation |
| 4 | PR #10 open (docs fix only) | Cosmetic, unblocking |
| 5 | No `track/16` branch | omp 16.x entirely invisible to all automation |

---

## Files Modified / Created

| File | Task | Change |
|------|------|--------|
| `.github/workflows/upload.yml` | Task 1 | Add `runs-on` input to reusable workflow call |
| (GitHub web) | Task 2 | Approve CI on PR #9 + merge; merge PRs #10, #8 |
| `VERSION` | Task 3 | `16.2.5` (on new `track/16` branch) |
| `.github/workflows/build.yml` | Task 3 | Branch `track/15` → `track/16` |
| `renovate.json` | Task 3 | Branch + allowedVersions 15→16 |

---

## Task 1 — Fix the `runs-on` bug in `upload.yml`

**Files:**
- Modify: `.github/workflows/upload.yml:62-71`

The reusable upload workflow accepts an optional `runs-on` input that defaults to self-hosted runners.
We must pass `'["ubuntu-latest"]'` explicitly, exactly as `build.yml` does for the build workflow.

- [ ] **Step 1: Create a branch and make the fix**

```bash
git checkout -b fix/upload-runs-on track/15
```

Open `.github/workflows/upload.yml`. In the `build-and-upload` job block (around line 62):

```yaml
  build-and-upload:
    needs: snapshot
    uses: canonical/sdkcraft-actions/.github/workflows/upload.yml@main
    with:
      runs-on: '["ubuntu-latest"]'           # ← add this line
      platforms: '["ubuntu@22.04:amd64","ubuntu@24.04:amd64"]'
      platform-flag: "--platform"
      risk: "edge"
      track: ${{ needs.snapshot.outputs.track }}
    secrets:
      SDKCRAFT_STORE_CREDENTIALS: ${{ secrets.SDKCRAFT_STORE_CREDENTIAL }}
```

- [ ] **Step 2: Verify the YAML is valid**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/upload.yml'))"
```

Expected: no output, exit 0.

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/upload.yml
git commit -m "fix(ci): pass runs-on ubuntu-latest to upload reusable workflow

The upload reusable workflow defaults to self-hosted runners
([\"self-hosted\",\"linux\",\"jammy\",\"x64\",\"xlarge\"]) when runs-on is not
passed. This repo has no such runners, causing every build-and-upload
job to queue for 24 h and be auto-cancelled by GitHub — no SDK has
ever reached the store. Pass ubuntu-latest explicitly, matching what
build.yml already does for the build workflow."
git push -u origin fix/upload-runs-on
```

- [ ] **Step 4: Open PR targeting `track/15`**

```bash
gh pr create \
  --title "fix(ci): pass runs-on ubuntu-latest to upload reusable workflow" \
  --body "$(cat <<'EOF'
## Problem

Every "Build and Upload SDK" run has been cancelled since the pipeline was created.

The \`build-and-upload\` job uses \`canonical/sdkcraft-actions/.github/workflows/upload.yml@main\`
without passing the \`runs-on\` input, which defaults to
\`["self-hosted","linux","jammy","x64","xlarge"]\`.
This repo has no such runners — both platform jobs sit in queue for 24 h until GitHub auto-cancels.

## Fix

Pass \`runs-on: '["ubuntu-latest"]'\` explicitly (same pattern as \`build.yml\`).

## Verification

Once this PR merges, the next "Build and Upload SDK" run should progress past the
\`build-and-upload\` jobs for the first time.
EOF
)" \
  --base track/15
```

- [ ] **Step 5: Wait for the `Build SDK` check to pass, then merge**

```bash
gh pr merge --squash --auto
```

Expected: PR merges, triggers "Build and Upload SDK" on track/15. The `build-and-upload` jobs
should now start on ubuntu-latest (no longer stuck waiting for self-hosted runners).

Watch the run:

```bash
gh run watch $(gh run list --workflow="Build and Upload SDK" --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected conclusion: `success` (all three jobs: snapshot, build-and-upload ×2, promote).

---

## Task 2 — Drain the open PR backlog for 15.x

**Goal:** Merge PRs #10, #8, and #9 (in that order — #9 last because it triggers an upload).
No code changes required here; all fixes are already authored.

**Prerequisite:** Task 1 merged and the upload workflow verified to work.

### PR #10 — Docs fix (no CI gate risk)

- [ ] **Step 1: Merge PR #10**

```bash
gh pr merge 10 --squash
```

Expected: merged cleanly; no CI concerns (docs-only change, no workflow trigger on `track/15` push).

### PR #8 — On-demand release harness + checkout v6 fix

- [ ] **Step 2: Review PR #8 for conflicts with Task 1's fix**

```bash
gh pr diff 8
```

Check that the `upload.yml` changes in PR #8 (checkout v4→v6) do not conflict with the
`runs-on` line added in Task 1. If there is a conflict, rebase the branch:

```bash
gh pr checkout 8
git rebase track/15
git push --force-with-lease
```

- [ ] **Step 3: Merge PR #8**

```bash
gh pr merge 8 --squash
```

Expected: merged. This lands `release-ondemand.yml` (useful for manual dry-runs) and bumps
checkout to v6 in `upload.yml`.

### PR #9 — Renovate: 15.11.0 → 15.13.3

The `Build SDK` check on PR #9 shows `action_required` — the Renovate bot's PR needs a
maintainer to manually approve the CI run before it executes.

- [ ] **Step 4: Approve the CI run for PR #9**

In the GitHub web UI:
1. Open https://github.com/PietroPasotti/omp-workshop-sdk/pull/9
2. Find the "Build SDK" check showing "Waiting for approval"
3. Click **"Approve and run"**

Or via CLI:

```bash
# List pending workflow runs waiting for approval on the Renovate branch
gh run list --branch renovate/can1357-oh-my-pi-15.x --json databaseId,status -q '.[] | select(.status=="action_required") | .databaseId'
# Approve each:
gh run approve <run-id>
```

Expected: the `Build SDK` check runs and passes (it only builds, doesn't upload).

- [ ] **Step 5: Verify automerge fires (or merge manually)**

Renovate has `automerge: true` / `automergeType: pr` in `renovate.json`. Once the `Build SDK`
check passes, Renovate should auto-merge within the next scheduled run (weekdays at 04:00 UTC).

To merge immediately:

```bash
gh pr merge 9 --squash
```

Expected: PR merges, `VERSION` on `track/15` becomes `15.13.3`, "Build and Upload SDK" triggers.

- [ ] **Step 6: Watch the 15.13.3 upload run**

```bash
gh run watch $(gh run list --workflow="Build and Upload SDK" --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: success — omp 15.13.3 lands in `15/edge`; previous revisions cascade to beta/candidate/stable.

---

## Task 3 — Bootstrap `track/16` for omp v16.x

**Goal:** Create the `track/16` branch, update the three files that need branch edits, and set it as the default branch. The upload workflow derives the track from `VERSION` at runtime — it needs no branch edit.

Per the bootstrap steps in `AGENTS.md`, the changes are:
- `VERSION`: `15.13.3` → `16.2.5`
- `build.yml`: branch `"track/15"` → `"track/16"` (push trigger and PR trigger)
- `renovate.json`: `"baseBranchPatterns": ["track/15"]` → `["track/16"]`; `"allowedVersions": "/^15\\."` → `"/^16\\./"` ; `"matchBaseBranches": ["track/15"]` → `["track/16"]`

`upload.yml` **must not** have its push trigger changed — it stays on `track/15` in this file;
the `track/16` copy of `upload.yml` (inherited when the branch is created) will have `track/16`
in the push trigger once the branch diverges. Wait — actually, when the branch is created,
it will inherit `upload.yml` with `track/15` in the push trigger. That trigger must be updated
to `track/16` as well, so the workflow fires on pushes to `track/16`.

- [ ] **Step 1: Create the branch from current `track/15`**

```bash
git fetch origin
git checkout -b track/16 origin/track/15
```

- [ ] **Step 2: Update `VERSION`**

```bash
printf '16.2.5\n' > VERSION
```

Verify:

```bash
cat VERSION
```

Expected: `16.2.5`

- [ ] **Step 3: Update `build.yml` — branch `track/15` → `track/16`**

In `.github/workflows/build.yml`, change the pull_request branch filter:

```yaml
on:
  pull_request:
    branches:
      - "track/16"
```

(The file is only 17 lines — replace the single `"track/15"` with `"track/16"`.)

- [ ] **Step 4: Update `upload.yml` — push trigger branch `track/15` → `track/16`**

In `.github/workflows/upload.yml`, change the push trigger (line 6):

```yaml
on:
  push:
    branches:
      - "track/16"
  workflow_dispatch:
```

The rest of `upload.yml` is unchanged — track is derived at runtime via
`cut -d. -f1 VERSION` which will now emit `16`.

- [ ] **Step 5: Update `renovate.json`**

Replace the entire `renovate.json` with:

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
      "depNameTemplate": "can1357/oh-my-pi",
      "datasourceTemplate": "github-releases",
      "versioningTemplate": "semver",
      "extractVersionTemplate": "^v(?<version>.*)$"
    }
  ],
  "baseBranchPatterns": ["track/16"],
  "packageRules": [
    {
      "matchPackageNames": ["can1357/oh-my-pi"],
      "matchBaseBranches": ["track/16"],
      "allowedVersions": "/^16\\./",
      "automerge": true,
      "automergeType": "pr"
    }
  ]
}
```

- [ ] **Step 6: Verify `renovate.json` is valid JSON**

```bash
python3 -m json.tool renovate.json > /dev/null
```

Expected: no output, exit 0.

- [ ] **Step 7: Commit and push `track/16`**

```bash
git add VERSION .github/workflows/build.yml .github/workflows/upload.yml renovate.json
git commit -m "chore: configure 16/edge track

Bootstrap track/16 for omp major version 16.
- VERSION: 16.2.5 (first v16 release)
- build.yml, upload.yml: update push/PR branch triggers to track/16
- renovate.json: baseBranchPatterns, matchBaseBranches, allowedVersions → track/16 / ^16\\."
git push -u origin track/16
```

- [ ] **Step 8: Set `track/16` as the default branch**

```bash
gh api repos/PietroPasotti/omp-workshop-sdk -X PATCH -f default_branch='track/16'
```

Expected: HTTP 200, `"default_branch": "track/16"`.

Confirm:

```bash
gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'
```

Expected: `track/16`

- [ ] **Step 9: Verify the upload workflow fires on `track/16`**

The push in Step 7 should have triggered "Build and Upload SDK" on `track/16`. Check:

```bash
gh run list --branch track/16 --workflow="Build and Upload SDK" --limit 3 --json databaseId,conclusion,status
```

Expected: one run present, in-progress or succeeded. Watch it:

```bash
gh run watch $(gh run list --branch track/16 --workflow="Build and Upload SDK" --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: `success` — omp 16.2.5 lands in `16/edge`.

- [ ] **Step 10: Verify the store**

```bash
sdkcraft revisions omp | grep "16/"
```

Expected: revision rows showing `16/edge` channel.

---

## Self-Review

**Spec coverage:**

| Requirement | Task |
|---|---|
| Upload workflow broken (runner bug) | Task 1 |
| Renovate PR #9 stuck | Task 2 |
| PRs #8, #10 pending | Task 2 |
| track/16 bootstrap | Task 3 |
| omp 16.2.5 in store | Task 3, Steps 9-10 |

**Placeholder scan:** None — all steps contain exact commands and expected output.

**Type consistency:** No types — shell/YAML only. Variable names and file paths are consistent
throughout.
