# omp-workshop-sdk

Workshop SDK that packages [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`),
an AI coding agent for the terminal.

## What this repo is

A Workshop SDK repo. It produces an SDK that installs the `omp` binary and
mounts `/home/workshop/.omp` from a Workshop-managed private host directory
(not the host's `~/.omp`) so config, sessions, Hindsight memory, and plugins
survive workshop updates. Users can run `workshop remount` to point the mount
at their real host `~/.omp` instead.

## Repo structure

```
sdkcraft.yaml          SDK definition (parts, plugs)
hooks/setup-base       Adds $SDK/bin to PATH; installs bash completions (runs as root)
hooks/check-health     Verifies omp --version (runs as root)
VERSION                Current upstream version (single line, e.g. 15.7.4)
renovate.json          Renovate config — watches can1357/oh-my-pi github-releases
.github/workflows/
  build.yml            PR check: builds on PRs targeting track/16
  upload.yml           Release: 3-job pipeline (snapshot → build+upload → promote)
                       uploads to 16/edge, then cascades old revisions down the belt
  renovate.yml         Renovate bot schedule (main branch only)
  renovate-check.yml   Validates renovate.json on PRs (main branch only)
.github/scripts/
  promote-pipeline.sh  Snapshot/promote/channel-revs helpers; $SDKCRAFT injectable
  promote-pipeline.test.sh  Bash test harness for the promotion script
```

## Upstream

- Package: `@oh-my-pi/pi-coding-agent` on npm (npm version = GitHub release version)
- GitHub: `https://github.com/can1357/oh-my-pi`
- Releases: `https://github.com/can1357/oh-my-pi/releases`
- Binary URL pattern: `https://github.com/can1357/oh-my-pi/releases/download/v{VERSION}/omp-linux-x64`
  (raw binary, no archive)
- Version scheme: semver (e.g. 15.7.4); release tags are `v15.7.4`

## Key design facts

- **Multi-base**: `ubuntu@22.04:amd64` + `ubuntu@24.04:amd64` (no `build-base` field)
- **Track**: `16/edge` — branch `track/16`, one branch per upstream major under `track/*`;
  track number derived at runtime from the major in `VERSION` (not hardcoded in upload.yml)
- **Persistence**: single mount plug `omp-home` → `/home/workshop/.omp`
  All omp state (agent.db, history.db, sessions/, memories/, plugins/, python-env/) lives there.
  Host source is a private directory Workshop allocates under `$XDG_DATA_HOME` — an SDK cannot
  mount an arbitrary host path. Users override with
  `workshop remount <ws>/omp:omp-home ~/.omp` (stop workshop first).
- **No network service**: omp is a CLI tool; no tunnel slot needed
- **No GPU plug**: omp calls external AI APIs, no local GPU needed
- **Binary is self-contained**: Bun `--compile` output; no system runtime deps required

## Branch/CI structure

- `track/16`: default branch — has VERSION, all workflows (build, upload, Renovate)
- `track/15`: legacy 15.x maintenance branch — Renovate **does not** update it
  (Renovate runs only from the default branch and reads `renovate.json` there)
- No `main` branch; Renovate runs from the default branch on a weekday-04:00-UTC schedule

**First Renovate PR on a fresh repo or branch** may show `action_required` on the
`Build SDK` check — click "Approve and run" once; subsequent Renovate PRs run automatically.

To bootstrap a new major-version branch (e.g., `track/17` when upstream goes to 17.x):
1. `git checkout -b track/17 track/16`
2. Update `VERSION` to the first 17.x release
3. Update `build.yml`: `branches: "track/16"` → `"track/17"`
4. Update `upload.yml`: push trigger `branches: "track/16"` → `"track/17"`
   (the track number in the pipeline is still derived at runtime from `VERSION`; only the
   push trigger line changes)
5. Update `renovate.json`: `baseBranchPatterns`, `matchBaseBranches` → `["track/17"]`;
   `allowedVersions` → `"/^17\\./"`
6. `git commit -m "chore: configure 17/edge track" && git push -u origin track/17`
   Note: the `build-sdk-checks` ruleset (pattern `refs/heads/track/*`) blocks direct pushes
   to new track branches. If the push is rejected with "required status check expected",
   temporarily disable enforcement:
   `gh api repos/<owner>/omp-workshop-sdk/rulesets/17107028 -X PATCH -f enforcement=disabled`
   Push, then immediately re-enable:
   `gh api repos/<owner>/omp-workshop-sdk/rulesets/17107028 -X PATCH -f enforcement=active`
7. `gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch='track/17'`
8. `sdkcraft create-track omp --track 17`
   (required before the first upload — the release step fails silently if the store track
   does not exist: the binary uploads but channel assignment is rejected)

## Iterate locally

```bash
sdkcraft try --verbose
# edit workshop.yaml to use try-omp
workshop launch
workshop shell
omp --version
workshop info   # check health
```
