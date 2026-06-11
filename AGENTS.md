# omp-workshop-sdk

Workshop SDK that packages [oh-my-pi](https://github.com/can1357/oh-my-pi) (`omp`),
an AI coding agent for the terminal.

## What this repo is

A Workshop SDK repo. It produces an SDK that installs the `omp` binary and
mounts `~/.omp/` from the host so config, sessions, Hindsight memory, and
plugins survive workshop updates.

## Repo structure

```
sdkcraft.yaml          SDK definition (parts, plugs)
hooks/setup-base       Adds $SDK/bin to PATH; installs bash completions (runs as root)
hooks/check-health     Verifies omp --version (runs as root)
VERSION                Current upstream version (single line, e.g. 15.7.4)
renovate.json          Renovate config — watches can1357/oh-my-pi github-releases
.github/workflows/
  build.yml            PR check: builds on PRs targeting track/15
  upload.yml           Release: 3-job pipeline (snapshot → build+upload → promote)
                       uploads to 15/edge, then cascades old revisions down the belt
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
- **Track**: `15/edge` — branch `track/15`, one branch per upstream major under `track/*`;
  track number derived at runtime from the major in `VERSION` (not hardcoded in upload.yml)
- **Persistence**: single mount plug `omp-home` → `/home/workshop/.omp`
  All omp state (agent.db, history.db, sessions/, memories/, plugins/, python-env/) lives there
- **No network service**: omp is a CLI tool; no tunnel slot needed
- **No GPU plug**: omp calls external AI APIs, no local GPU needed
- **Binary is self-contained**: Bun `--compile` output; no system runtime deps required

## Branch/CI structure

- `track/15`: default branch — has VERSION, all workflows (build, upload, Renovate)
- No `main` branch; Renovate runs from the default branch

To bootstrap a new major-version branch (e.g., `track/16` when upstream goes to 16.x):
1. `git checkout -b track/16 track/15`
2. Update `VERSION` to the first 16.x release
3. Update `build.yml` and `renovate.json`: branch `"track/15"` → `"track/16"`,
   `allowedVersions: "/^16\\./"` (`upload.yml` needs no branch edit — track is derived from `VERSION`)
4. `git commit -m "chore: configure 16/edge track" && git push -u origin track/16`
5. `gh api repos/<owner>/omp-workshop-sdk -X PATCH -f default_branch='track/16'`

## Iterate locally

```bash
sdkcraft try --verbose
# edit workshop.yaml to use try-omp
workshop launch
workshop shell
omp --version
workshop info   # check health
```
