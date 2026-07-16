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
VERSION                Current upstream version (single line, e.g. 17.0.1)
renovate.json          Renovate config — watches can1357/oh-my-pi github-releases
.github/workflows/
  bootstrap-major.yml  Daily: detects upstream major bumps, creates the new track
  build.yml            PR check: builds on PRs targeting any track/* branch
  upload.yml           Release: 3-job pipeline (snapshot → build+upload → promote)
                       uploads to N/edge, then cascades old revisions down the belt
  renovate.yml         Renovate bot schedule (runs from the default branch)
  renovate-check.yml   Validates renovate.json on PRs
.github/scripts/
  promote-pipeline.sh  Snapshot/promote/channel-revs helpers; $SDKCRAFT injectable
  promote-pipeline.test.sh  Bash test harness for the promotion script
```

## Upstream

- Package: `@oh-my-pi/pi-coding-agent` on npm (npm version = GitHub release version)
- GitHub: `https://github.com/can1357/oh-my-pi`
- Releases: `https://github.com/can1357/oh-my-pi/releases`
- Binary URL pattern:
  `https://github.com/can1357/oh-my-pi/releases/download/v{VERSION}/omp-linux-{x64,arm64}`
  (raw binary, no archive; `override-pull` picks the asset from `CRAFT_ARCH_BUILD_FOR`)
- Version scheme: semver (e.g. 17.0.1); release tags are `v17.0.1`

## Key design facts

- **Multi-base + multi-arch**: `ubuntu@{22.04,24.04}:{amd64,arm64}` (no `build-base` field).
  arm64 is cross-built on amd64 (`build-on` amd64 / `build-for` arm64); the `dump` part only
  downloads a prebuilt binary, so no native arm64 runner or QEMU is needed. `upload.yml` builds
  and uploads all four platforms on the amd64 runner.
- **Track**: one `track/<N>` branch per upstream major; the current default is `track/17`
  (`17/edge`). Track number derived at runtime from the major in `VERSION`.
- **Persistence**: single mount plug `omp-home` → `/home/workshop/.omp`
  All omp state (agent.db, history.db, sessions/, memories/, plugins/, python-env/) lives there.
  Host source is a private directory Workshop allocates under `$XDG_DATA_HOME` — an SDK cannot
  mount an arbitrary host path. Users override with
  `workshop remount <ws>/omp:omp-home ~/.omp` (stop workshop first).
- **No network service**: omp is a CLI tool; no tunnel slot needed
- **No GPU plug**: omp calls external AI APIs, no local GPU needed
- **Binary is self-contained**: Bun `--compile` output; no system runtime deps required

## Branch/CI structure

- `track/17`: current default branch — VERSION, all workflows, Renovate
- `track/16`: legacy 16.x branch — receives no further Renovate updates
- No `main` branch; Renovate runs from the default branch on a weekday-04:00-UTC schedule

**First Renovate PR on a new track** may show `action_required` on the `Build SDK`
check — click "Approve and run" once; subsequent PRs on that track auto-run.

**Major-track bootstrapping is fully automated** by `bootstrap-major.yml` (daily 05:00 UTC).
When upstream exceeds the current default-branch major it creates `track/N`, updates
`renovate.json`, creates the store track, changes the default branch, and triggers the first
upload. Required secrets: `SDKCRAFT_STORE_TOKEN` (store auth) and `ADMIN_TOKEN` (fine-grained
PAT with Administration:write — used for the default-branch change; without it that step logs a
warning and the default branch must be changed manually once).

## Iterate locally

```bash
sdkcraft try --verbose
# edit workshop.yaml to use try-omp
workshop launch
workshop shell
omp --version
workshop info   # check health
```
