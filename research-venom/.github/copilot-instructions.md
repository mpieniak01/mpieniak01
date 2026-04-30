# Copilot Instructions (research-venom)

Scope for Copilot suggestions in this repository:

1. This is a research scripts project, not a frontend web app.
2. Start operational work from `make help`. Prefer Makefile targets over guessing script commands.
3. Prefer changes in:
   - `tools/`
   - `config/`
   - `docs/`
   - `tests/`
   - `artifacts/inputs/`
   - `artifacts/sources/`
   - `artifacts/processing/`
   - `artifacts/products_light/`
   - `artifacts/meta/`
4. `docs_pr/` is internal operational notes and is not a publication target.
5. Keep scripts deterministic and review-friendly:
   - explicit file paths from central config,
   - clear logs,
   - no hidden side effects.
6. Test policy:
   - use `make test-contracts` for logic-contract tests,
   - use `make test-static` for Python/help checks,
   - use `make test-powershell-parse` for PowerShell parser checks,
   - do not run `data_quality` tests in public CI.
7. API policy:
   - do not fetch GitHub/Sonar data implicitly,
   - use `CONFIRM_API=1 make fetch-*` only when the user explicitly asks to refresh data,
   - processing targets must work from existing local artifacts.
8. Office policy:
   - no Office COM requirement in CI,
   - use `make product-excel-only` or `make product-all` only when product generation is requested.
9. Export model:
   - use `export_research_pack.py --config ... --profile ...`,
   - do not suggest publishing whole workspace automatically.
