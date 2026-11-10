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
    channel: 18/stable
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

### Connect omp to a host `auth-gateway`

omp supports routing provider requests through a host-side
[`omp auth-gateway`](https://github.com/can1357/oh-my-pi/blob/main/docs/auth-broker-gateway.md)
instead of holding provider credentials inside the workshop. The gateway is a
forward-proxy (default `127.0.0.1:4000` on the host) that exposes
OpenAI/Anthropic-compatible routes and resolves credentials from an
`omp auth-broker` on your behalf; the workshop never sees the real provider
token, only the gateway's own bearer token.

The [`omp-auth-gateway`](https://snapcraft.io/omp-auth-gateway) snap runs
both as confined, auto-starting services, so this is mostly host setup, not
code:

```bash
sudo snap install omp-auth-gateway
```

This installs and enables `gateway-daemon` (`omp auth-gateway serve`, on
`127.0.0.1:4000`) and `broker-daemon` (`omp auth-broker serve`, on
`127.0.0.1:8765`), already wired to each other.

This SDK ships two plugs for this:

- `omp-gateway` (`tunnel`) — bridges to the host port where `auth-gateway serve` listens.
- `omp-gateway-token` (`secret`) — the gateway's bearer token, fetched on demand.

**1. On the host**, add a provider credential to the broker and fetch the
gateway's bearer token:

```bash
sudo snap alias omp-auth-gateway.broker omp-auth-broker   # one-time
sudo omp-auth-broker login anthropic
sudo omp-auth-gateway token   # prints the bearer token
```

**2. In your workshop definition**, add a matching `system` slot for each plug
and store the gateway token in your host keyring:

```bash
secret-tool store --label="omp gateway token" service omp-gateway
```

```yaml
sdks:
  - name: omp
    channel: 18/stable
  - name: system
    slots:
      omp-gateway:
        interface: tunnel
        endpoint: localhost:4000   # host port auth-gateway listens on
      omp-gateway-token:
        interface: secret
        attributes:
          service: omp-gateway
```

**3. Connect both plugs** (neither auto-connects — a host-service tunnel and
every `secret` plug require a manual connect):

```bash
workshop refresh
workshop connect <workshop>/omp:omp-gateway <workshop>/system:omp-gateway
workshop connect <workshop>/omp:omp-gateway-token <workshop>/system:omp-gateway-token
```

**4. Point a provider at the gateway** in `~/.omp/agent/models.yml`, using
omp's own `!<command>` config indirection to fetch the token at read time
instead of writing it to disk:

```yaml
providers:
  anthropic:
    baseUrl: http://localhost:4000
    apiKey: "!workshopctl get-secret omp.omp-gateway-token"
    api: anthropic-messages
```

The `baseUrl` shape depends on the route's wire format: `anthropic-messages`
takes the gateway root (`http://localhost:4000`, matching `api.anthropic.com`'s
own convention), while `openai-completions`/`openai-responses` need the
`/v1` suffix (`http://localhost:4000/v1`, matching `api.openai.com/v1`) —
the gateway always serves at `/v1/messages` / `/v1/chat/completions` /
`/v1/responses` regardless. Repeat the block (new `providers.<id>` key,
matching `api:` and `baseUrl` shape) for every provider you want routed
through the gateway instead of a locally-held key.

If the secret plug is disconnected, `workshopctl get-secret` fails and omp
falls back to its normal local credential resolution — the workshop stays
healthy either way.

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

### `omp-gateway`

- Interface: `tunnel`
- Endpoint: `localhost:4000`
- Purpose: Bridges to a host-side `omp auth-gateway serve` listener so omp can
  route provider requests through it instead of holding credentials directly.
  Not auto-connected — pair it with a `system` tunnel slot and
  `workshop connect`. See **Connect omp to a host `auth-gateway`** above.

### `omp-gateway-token`

- Interface: `secret`
- Purpose: The `auth-gateway`'s bearer token, fetched on demand with
  `workshopctl get-secret omp.omp-gateway-token`. Never auto-connected and
  never written to disk by this SDK. See **Connect omp to a host
  `auth-gateway`** above.

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
