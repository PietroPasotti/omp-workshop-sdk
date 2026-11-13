# Oh My Pi SDK for Workshop

This SDK provides `omp`, the oh-my-pi AI coding agent. It ships with
hash-anchored edits, LSP integration, DAP debugging, persistent Python and
JavaScript eval kernels, first-class subagents, and 40+ AI provider
connections out of the box. Configuration, sessions, memory (Hindsight),
and plugins are persisted across workshop updates.

---

## Reference workshop

A minimal workshop:

```yaml
# workshop.yaml
name: my-project
base: ubuntu@24.04
sdks:
  - name: omp
    channel: 15/edge
```

This gives you `omp` on your PATH inside the workshop immediately after
`workshop launch`.

---

## Using the SDK

### Prerequisites, project layout

1. No prerequisite SDKs are required.
2. No specific project layout is needed. `omp` operates in any directory.
3. On launch, the SDK adds `omp` to `PATH` and installs bash completions.
   `/home/workshop/.omp` (config, sessions, API keys, plugins, Hindsight
   memory) is backed by a Workshop-managed private host directory — it persists
   across workshop stop/refresh and SDK updates, but it is **not** your existing
   host `~/.omp`; a fresh workshop starts empty. See **Use your host's `~/.omp`**
   below to opt in.

### Running the agent

```bash
workshop shell

# Start an interactive session in your project
cd /project
omp

# Non-interactive one-shot
omp "explain the architecture of this codebase"

# Resume the most recent session
omp --resume

# Commit staged changes with atomic, dependency-ordered commits
omp commit
```

### Configure API keys

Settings live in `~/.omp/agent/settings.yml` (or via `omp config`):

```bash
workshop shell
omp config set providers.anthropic.apiKey sk-ant-...
```

All changes are persisted to a Workshop-managed host directory through the
`omp-home` mount and survive SDK updates.

### Guardrails: the write/network jail

Every `omp` invocation runs inside a self-imposed, kernel-enforced jail —
no host configuration, no `lxc config`, nothing outside this SDK. It uses
two independent, unprivileged Linux mechanisms (verified against the exact
Workshop `lxd-container` runtime, not just in theory):

- A private mount namespace (`unshare --user --mount`) bind-remounts a
  fixed set of paths **read-only** before `omp` ever starts:
  `.git/hooks`, `.git/config`, every `.env*` file at the project root,
  `.github/workflows`, and `deploy/` (all relative to `/project`; a path
  that doesn't exist is skipped). This is what stops hook injection,
  `.git/config` tampering (e.g. rewriting `core.hooksPath`), secret-file
  writes, and CI/deploy tampering — note it's `.git/hooks` and
  `.git/config` specifically, not all of `.git`: normal `git add`/
  `git commit`/`git merge` keep working, since they write to
  `.git/objects`, `.git/index`, and `.git/refs`, not the two protected
  files.
- A [Landlock](https://docs.kernel.org/userspace-api/landlock.html) ruleset
  then denies every file write/create/remove/rename and outbound TCP
  connect everywhere **except** `/project`, `~/.omp`, and `/tmp` (writes)
  and ports `443`, `80`, and `4000` (connects) — granted recursively, so
  creating brand-new top-level files and directories in `/project` still
  works. `/dev/null`, `/dev/zero`, `/dev/full`, `/dev/random`, and
  `/dev/urandom` stay writable everywhere too — redirecting to `/dev/null`
  is near-universal (git itself does it) and discarding/reading bytes
  there has no write-side security implication. Capabilities are dropped
  and `no_new_privs` is set first, so neither `sudo` nor a retained
  `CAP_SYS_ADMIN` can undo any of this from inside the jailed process
  tree. Reads are never restricted — this is a write/network guardrail,
  not a read sandbox.

Tune or disable it with environment variables (set them before `omp` runs,
e.g. in `~/.profile` or the invoking shell):

```bash
# Add more read-only paths, relative to /project, space-separated
export OMP_JAIL_EXTRA_RO="secrets.yaml infra/terraform"

# Change the allowed outbound TCP ports (comma-separated)
export OMP_JAIL_CONNECT_TCP="443,80,4000,8443"

# Bypass the jail entirely for this invocation
OMP_JAIL=0 omp ...
```

### Shell completions

Bash completions are installed automatically. For other shells:

```bash
workshop shell

# zsh
eval "$(omp completions zsh)"

# fish
omp completions fish > ~/.config/fish/completions/omp.fish
```

### Verify from the command line

```bash
workshop shell
omp --version
```

---

## Plugs (resources this SDK consumes)

### `omp-home`

- Interface: `mount`
- Workshop target: `/home/workshop/.omp`
- Purpose: Persists all of omp's state — agent config and API keys
  (`~/.omp/agent/settings.yml`), session history (`history.db`), Hindsight
  memory (`memories/`), installed plugins (`plugins/`), and the Python eval
  environment (`python-env/`) — across workshop updates. The host source is a
  private directory Workshop allocates under `$XDG_DATA_HOME` (not your existing
  host `~/.omp`); a fresh workshop starts empty.

### Use your host's `~/.omp`

By default Workshop mounts a private host directory into `/home/workshop/.omp`.
To use your real host `~/.omp` instead, run these commands **on the host**
(the workshop must be stopped first because `~/.omp` is not empty):

```bash
workshop stop <workshop>
workshop remount <workshop>/omp:omp-home ~/.omp
workshop start <workshop>
```

The mount is read-write: omp will read and write your host `~/.omp` directly.

To revert to the private Workshop-managed directory:

```bash
workshop disconnect <workshop>/omp:omp-home --forget
workshop refresh <workshop>
```

---

## Documentation and guidance

- [Oh My Pi documentation](https://omp.sh)
- [Workshop documentation](https://ubuntu.com/workshop/docs/)
- [DEVELOPERS.md](DEVELOPERS.md) — branch model, release automation, bootstrapping a new major
- [AGENTS.md](AGENTS.md) — quick-restart context for AI coding agents working in this repo

---

## Community and support

- Oh My Pi community:
  [Discord](https://discord.gg/4NMW9cdXZa)
- Workshop forum:
  [Discourse](https://discourse.ubuntu.com/)
- Please review our
  [Code of Conduct](https://ubuntu.com/community/ethos/code-of-conduct) before
  participating.

---

## Contributions

All contributions, including code, documentation updates, and issue reports,
are welcome!

- See `CONTRIBUTING.md` for guidelines.
- Open issues or pull requests on the official repository.

---

## License and copyright

Copyright 2026 Canonical Ltd.

This SDK is released under the [MIT License](https://www.gnu.org/licenses/gpl-3.0).

Oh My Pi is licensed under the
[MIT License](https://github.com/can1357/oh-my-pi/blob/main/LICENSE).
