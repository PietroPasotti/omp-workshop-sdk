# README Template

All SDK READMEs follow a consistent structure. This template is derived from
the patterns used across copilot-sdk, node-sdk, jupyter-sdk, and others.

## Structure

Every README has these sections in order:

1. **Title** — `# [Software Name] SDK for Workshop`
2. **Overview paragraph** — 2-3 sentences matching sdkcraft.yaml description
3. **Reference workshop** — minimal workshop.yaml example
4. **Using the SDK** — prerequisites, primary workflow, verification
5. **Plugs** — one subsection per plug
6. **Slots** — one subsection per slot (or "doesn't define any slots")
7. **Documentation and guidance** — upstream docs + Workshop docs
8. **Community and support** — upstream community + Workshop Discourse + CoC
9. **Contributions** — CONTRIBUTING.md reference
10. **License and copyright** — copyright year, license, upstream license

## Rules

- The overview paragraph should closely match `sdkcraft.yaml` `description`
- Use `workshop updates` (not "restarts" or "sessions") for persistence language
- Channel in reference workshop: `<track>/stable` (e.g., `latest/stable`, `22/stable`)
- Do NOT include "Installed components" or "Platforms, channels, versions" sections
- Focus on SDK behavior, not upstream product marketing
- All command examples must distinguish host vs workshop context
- Use `---` horizontal rules between major sections

## Template

```markdown
# [Software Name] SDK for Workshop

[Overview: what it provides, what it persists, notable features. 2-3
sentences matching sdkcraft.yaml description.]

---

## Reference workshop

A minimal workshop:

\`\`\`yaml
# workshop.yaml
name: [example-name]
base: ubuntu@24.04
sdks:
  - name: [sdk-name]
    channel: [track]/stable

[actions:
  example-action: |
    example-command]
\`\`\`

[1-2 sentences explaining what the reference demonstrates.]

---

## Using the SDK

### Prerequisites, project layout

1. [Prerequisite SDKs or "No prerequisite SDKs are required."]
2. [Project layout requirements or "No specific project layout is needed."]
3. [What happens on launch — what the SDK configures automatically.]

### [Primary workflow heading]

[Step-by-step usage with code examples.]

\`\`\`bash
workshop shell
[commands inside workshop]
\`\`\`

### Verify from the command line

[How to confirm the SDK is working.]

\`\`\`bash
workshop shell
[verification commands]
\`\`\`

---

## Plugs (resources this SDK consumes)

### `[plug-name]`

- Interface: `[mount|gpu|tunnel|desktop|ssh]`
- Workshop target: `[path]`
- [Mode: `0o700` — if applicable]
- Purpose: [What it persists/provides and why.]

## Slots (resources this SDK provides)

### `[slot-name]`

- Interface: `[tunnel|mount]`
- Endpoint: `[port]` / Workshop source: `[path]`
- Purpose: [What it exposes.]

[Or: "This SDK doesn't define any slots."]

---

## Documentation and guidance

- [Upstream official documentation](https://example.com/docs)
- [Workshop documentation](https://canonical-workshop.readthedocs-hosted.com/latest/)

---

## Community and support

- [Upstream] community:
  [Community link](https://example.com/community)
- Workshop forum:
  [Workshop Discourse](https://discourse.canonical.com/c/engineering/workshops/34)
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

Copyright [year] Canonical Ltd.

[License statement with link.]

[Upstream software] is licensed under the
[License Name](https://license-url).
```

## Description Field Guidelines

The `description` field in sdkcraft.yaml should match the README overview:

```yaml
description: |
  This SDK provides [toolchain/runtime] for [purpose].
  [Key resources] are persisted on the host to speed up [builds/installs]
  across workshop updates.
```

Keep it as a short YAML multiline string. No sub-headings, no bullet lists
in the short form. Extended descriptions with `## Key components` and
`## Setup actions` sub-sections are acceptable for complex SDKs (see node-sdk,
go-sdk patterns).
