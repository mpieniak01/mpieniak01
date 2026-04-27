# Copilot Instructions (research-venom scope)

Scope for Copilot suggestions in this repository:

1. Prioritize work inside `research-venom/`.
2. This is a research scripts project, not a frontend web app.
3. Prefer changes in:
   - `research-venom/tools/`
   - `research-venom/config/`
   - `research-venom/205F/inputs/`
4. Do not propose DOM/UI work, React components, CSS, or browser code unless explicitly requested.
5. Keep scripts deterministic and review-friendly:
   - explicit file paths from config,
   - clear logs,
   - no hidden side effects.
6. For CI and validation:
   - focus on syntax/parse checks and dry-run workflows,
   - avoid requiring local Office/COM during CI.
7. Preserve whitelist publication model:
   - export only through manifest files in `research-venom/config/`,
   - do not suggest publishing whole workspace automatically.
