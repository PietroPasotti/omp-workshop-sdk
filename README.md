<!--
# SDK README Template for Workshop

OVERALL DESIGN (for sdkcraft.yaml description field):

The sdkcraft.yaml `description` field should match the README overview
paragraph so it can be reused in `sdk info` output. Write it as a short YAML
multiline string — no sub-headings, no bullet lists. Follow this pattern:

description: |
  This SDK provides [toolchain/runtime] for [purpose].
  [Key resources] are persisted on the host to speed up [builds/installs]
  across workshop updates.

Examples from approved SDKs:

  # go
  description: |
    This SDK provides the official Go toolchain for efficient Go
    development. Module downloads are persisted on the host to speed up builds
    across workshop updates, and Go environment settings are preserved between
    workshop updates.

  # node
  description: |
    This SDK provides a complete Node.js development environment built from
    source, with Corepack enabled for flexible package manager choice. Package
    manager caches are persisted on the host to speed up dependency
    installations across workshop updates.

README TEMPLATE INSTRUCTIONS:

1. Copy this file to your SDK repository directory as README.md
2. Replace all placeholders in [SQUARE BRACKETS] with your actual content;
   replace XYZ, FOO, BAR with real product names
3. Remove any sections that don't apply to your SDK for simplicity
4. Delete this comment block before publishing
5. Test all command examples before publishing

Focus on the SDK's behavior, not the target library/framework documentation.
Link to upstream docs for product-related specifics.

Do NOT include "Installed components" or "Platforms, channels, versions"
sections. Component details should be folded into the overview paragraph.
Channel information belongs in `sdk info`, not the README.

SECTION GUIDE:

Title and description:
Use the format "[Software Name] SDK for Workshop". Answer: What is it?
What does it do? Who is it for? Keep it 2-3 compound sentences long.
Focus on how the SDK affects the user's environment, not on marketing
language. Avoid phrases like "focus on writing and testing code".

Reference workshop:
Provide an inline minimal workshop.yaml.
Explain briefly what the reference demonstrates.

Using the SDK:
Step-by-step: prerequisite SDKs, project layout, launch, primary workflow.
All commands must be tested and working. Keep code examples clear about
whether they run on the host or inside the workshop.

Plugs and slots:
Document each plug: interface, target/source, purpose.
Include mounts and persistence details here, and document any tunnels
alongside other plug types.
If the SDK relies on resources exposed by other SDKs, say this explicitly.
Do the same for slots if SDK exposes resources to others.
Use "workshop updates" (not "restarts" or "sessions") when describing
what mounts survive.

Documentation and guidance:
Link to upstream docs.

Community and support:
Link to forums, support channels, Code of Conduct.

Contributions:
Link to contribution guides, CONTRIBUTING.md.

License and copyright:
Include copyright holder, year, license name and link.
Make sure to include all shipped components.
-->

# [Software Name] SDK for Workshop

[Brief description of what this SDK provides. Should closely match the
sdkcraft.yaml description. Focus on how the SDK affects the development
environment: what toolchain/runtime it provides, what it persists on the host,
and any notable features. Example: "A development environment for Go projects.
It provides the official Go toolchain, manages module caches via persistent
mounts, and preserves Go environment settings across workshop updates."]

---

## Reference workshop

A minimal workshop:

```yaml
# workshop.yaml
name: [workshop-name]
base: ubuntu@[version]  # e.g., ubuntu@24.04
sdks:
  - name: [sdk-name]
    channel: [channel]  # e.g., 1.24/stable

actions:
  [action-name]: |
    [command]
```

[One sentence explaining what this demonstrates, e.g., "This demonstrates a
basic Go build workflow with persistent module caching."]

---

## Using the SDK

### Prerequisites, project layout

1. [List prerequisites, e.g., "This relies on the `uv` SDK for venv."]
2. [Suggest expected project directory structure, including source code layout
   and setup steps needed:]

   ```bash
   [command to clone or prepare sources]
   ```

3. [Describe what side effects may happen during launch and refresh.]

### [Primary workflow task, e.g., "Build the project"]

Once the workshop is ready:

```bash
[workshop run]
[commands to perform the primary task]
```

[Explain where outputs go and how they persist across workshop updates.]

### [Secondary workflow task, e.g., "Test and run"]

From within the workshop shell:

```bash
workshop shell
[test or run commands]
```

[Brief explanation of what this achieves.]

---

## Plugs (resources this SDK consumes)

### `[plug-name]`

- Interface: `mount`
- Workshop target: `[/path/inside/workshop]`
- Purpose: [What this persists between workshop updates.]

### `[plug-name]`

- Interface: `gpu`
- Purpose: Grants access to [AMD/NVIDIA] GPU hardware on the host.

-- OR --

This SDK doesn't define any plugs.

## Slots (resources this SDK provides)

### `[slot-name]`

- Interface: `mount`
- Workshop source: `[/path/inside/workshop]`
- Purpose: [What resource this exposes to other SDKs]

-- OR --

This SDK doesn't define any slots.

---

## Documentation and guidance

- [[XYZ] official documentation]([upstream-docs-url])
- [[XYZ] best practices]([public-website-url])

---

## Community and support

- [XYZ] community forum: [Link to upstream forum/community]
- Please review our [Code of Conduct](https://ubuntu.com/community/ethos/code-of-conduct)
  before participating.

---

## Contributions

All contributions, including code, documentation updates, and issue reports,
are welcome!

- See [CONTRIBUTING]([public-github-url]) for guidelines.
- Open issues or pull requests on the [official repository]([repo-url]).

---

## License and copyright

Copyright [START YEAR] [COPYRIGHT HOLDER].

[Include any required claims, information, and disclaimers for your license.]
