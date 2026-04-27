# Research-Venom Copilot Instructions

> Note: in this repository the active Copilot instructions are at `/.github/copilot-instructions.md`.
> This file is kept as part of the portable `research-venom` package.

Scope for Copilot suggestions in this repository:

1. This is a **research scripts** project, not a frontend web app.
2. Prefer changes in:
   - `tools/`
   - `config/`
   - `205F/inputs/`
3. Do not propose DOM/UI work, React components, CSS, or browser code unless explicitly requested.
4. Keep scripts deterministic and review-friendly:
   - explicit file paths from config,
   - clear logs,
   - no hidden side effects.
5. For CI and validation:
   - focus on syntax/parse checks and dry-run workflows,
   - avoid requiring local Office/COM during CI.
6. Preserve whitelist publication model:
   - export only through manifest files in `config/`,
   - do not suggest publishing whole workspace automatically.
