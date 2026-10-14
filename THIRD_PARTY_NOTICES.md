# Third-Party Notices

The TOML parser is vendored from `toml++` v3.4.0 by Mark Gillard, licensed
under MIT. Its single-header distribution and license are in
[`third_party/tomlplusplus`](third_party/tomlplusplus).

The selected skills are vendored from `sickn33/agentic-awesome-skills` release
`v16.1.0`, verified at commit
`58d857988fcfac6986206bca2b2fe223aa437e4b`. The npm package integrity is pinned
in [`docs/ai/aas-stack.json`](docs/ai/aas-stack.json). The catalog repository is MIT licensed;
the catalog's source attribution table is authoritative for imported content.

| Vendored skill | Pinned source | License / attribution |
| --- | --- | --- |
| `architecture` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/architecture) | AAS catalog MIT; entry does not declare a separate license |
| `cpp-pro` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/cpp-pro) | AAS catalog MIT; entry does not declare a separate license |
| `memory-safety-patterns` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/memory-safety-patterns) | AAS catalog MIT; entry does not declare a separate license |
| `code-refactoring-refactor-clean` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/code-refactoring-refactor-clean) | AAS catalog MIT; entry does not declare a separate license |
| `code-review-and-quality` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/code-review-and-quality) | MIT; source [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills/blob/main/LICENSE) |
| `systematic-debugging` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/systematic-debugging) | AAS catalog MIT; entry does not declare a separate license |
| `test-driven-development` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/test-driven-development) | AAS catalog MIT; entry does not declare a separate license |
| `cross-platform-contract-propagation-audit` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/cross-platform-contract-propagation-audit) | `source: self`; no separate license declared |
| `api-and-interface-design` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/api-and-interface-design) | MIT; source [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills/blob/main/LICENSE) |
| `ai-native-cli` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/ai-native-cli) | AAS catalog MIT; upstream [agent-cli-spec](https://github.com/ChaosRealmsAI/agent-cli-spec) is cited in metadata |
| `threat-modeling-expert` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/threat-modeling-expert) | AAS catalog MIT; entry does not declare a separate license |
| `api-security-best-practices` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/api-security-best-practices) | AAS catalog MIT; entry does not declare a separate license |
| `orchestrate-batch-refactor` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/orchestrate-batch-refactor) | MIT; source [Dimillian/Skills](https://github.com/Dimillian/Skills) |
| `review-multi-agent-orchestration` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/review-multi-agent-orchestration) | `source: self`; no separate license declared |
| `acceptance-orchestrator` | [AAS v16.1.0](https://github.com/sickn33/agentic-awesome-skills/tree/58d857988fcfac6986206bca2b2fe223aa437e4b/skills/acceptance-orchestrator) | AAS catalog MIT; entry does not declare a separate license |

Only the selected skill directories are vendored here. No complete AAS catalog,
catalog documentation, executable, package manager, or runtime dependency is
vendored here.
## Yabai scripting addition integration

The optional absolute-transform integration patches Yabai 7.1.25, commit
`02de172f8706c3e2eaa679478897d7346e82b564`, by Åsmund Vikane and contributors.
Yabai is MIT licensed. Its license is included in
`integrations/yabai/LICENSE.txt`; upstream source is downloaded only into the
local build directory by `tools/build_yabai_sa.py`.
