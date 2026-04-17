---
name: sdk-designer
description: "Design and build Workshop SDKs from scratch. USE FOR: creating new sdkcraft.yaml, hooks, plugs/slots, services, README, renovate.json, CI workflows; onboarding SDKs with VERSION files and version branches; iterating on SDK design with sdkcraft try/test. DO NOT USE FOR: workshop.yaml authoring (that's the consumer side); general shell scripting; unrelated CI/CD."
argument-hint: "Describe what software the SDK should package and any known requirements"
---

# SDK Designer

Design, build, test, and onboard Workshop SDKs.

## When to Use

- Creating a new SDK from scratch for Workshop
- Onboarding an existing SDK repo (VERSION, renovate, CI, branches)
- Adding or modifying hooks, plugs, slots, or services
- Writing an SDK README
- Iterating on an SDK with `sdkcraft try` / `sdkcraft test`

## Procedure

Follow these phases in order. Each phase has a reference file with detailed
patterns, templates, and decision trees.

### Phase 1 — Requirements Gathering

Before writing any file, determine:

1. **What software** is being packaged (runtime, toolchain, service, AI agent)?
2. **How is it distributed** upstream (tarball, npm, PyPI, apt, git repo, snap)?
3. **What needs to persist** across workshop updates (caches, config, models)?
4. **Does it expose a network service** (web UI, API server, debug port)?
5. **Does it need hardware access** (GPU, camera, desktop)?
6. **Single base or multi-base?** Does it need to work on multiple Ubuntu versions?
7. **Single arch or multi-arch?** (amd64 only, or also arm64/riscv64?)
8. **What is the upstream version scheme?** (semver, calver, codename?)
9. **What is the upstream datasource for Renovate?** (npm, pypi, github-releases, node-version, golang-version?)
10. **How many version tracks?** Single `latest` channel, or multiple major/minor branches?

If information is missing or ambiguous, ask the user before proceeding.

### Phase 2 — Design

Use the [SDK Patterns Reference](./references/sdk-patterns.md) to make design
decisions:

1. **Choose the platform layout** — single-base (`build-base`) vs multi-base
   (multiple `ubuntu@` entries in `platforms`)
2. **Choose the parts strategy** — plugin type (nil, dump, npm, rust, cmake,
   make), source acquisition, override-pull/build
3. **Choose the interface layout** — mount plugs for persistence, gpu/desktop/ssh
   plugs for hardware, tunnel slots for services, mount slots for sharing
4. **Choose the hooks** — which of setup-base, setup-project, check-health,
   save-state, restore-state are needed
5. **Decide parts vs hooks** — ship pre-built binaries in parts, or install
   dynamically in hooks (apt packages → hooks; pinned binaries → parts)

### Phase 3 — Implement

Create the SDK files in this order:

1. **sdkcraft.yaml** — metadata, platforms, parts, plugs, slots
2. **hooks/** — setup-base, setup-project, check-health, etc.
3. **services/** — systemd unit files (if the SDK runs a daemon)
4. **VERSION** — single line with the current upstream version
5. **renovate.json** — Renovate config for automated version updates
6. **.github/workflows/** — build.yml, upload.yml (CI/CD)
7. **README.md** — following the [README Template](./references/readme-template.md)

Use the [sdkcraft.yaml Reference](./references/sdkcraft-reference.md) for
the exact field specifications and the
[Hooks Reference](./references/hooks-reference.md) for hook patterns.

### Phase 4 — Build, Test, Iterate

Follow the [Build-Test-Iterate Workflow](./references/build-test-iterate.md)
to validate the SDK locally before publishing:

```
sdkcraft try → workshop launch → workshop shell → verify → iterate
```

### Phase 5 — Onboard for CI

Follow the [Onboarding Reference](./references/onboarding.md) for the git
branching and CI setup:

1. Commit all files on main
2. Remove VERSION from main
3. Create version branch(es) from the commit with VERSION
4. Remove Renovate workflows from version branches
5. Push

### Phase 6 — Write README

Use the [README Template](./references/readme-template.md) to write a README
that matches the established pattern across all SDKs.
