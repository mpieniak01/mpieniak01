# Scripts Reference

## Zasada konfiguracji

Wszystkie skrypty korzystaja z centralnego configu:
- `config/process_pipeline_v01.json` dla legacy helperow i wejsc starszych krokow,
- `config/process_pipeline_v04.json` jako aktywna baza dla pipeline wizualizacji v4 i dopasowania do szablonu Excela.
- `config/process_pipeline_v04_test.json` jako baza testowa (sample inputs, bez ujawniania realnych list benchmarkowych).

Priorytet parametrow:
1. CLI
2. `config.process.steps`
3. `config.scripts`
4. fallback w skrypcie

Warstwa kompatybilnosci nie jest czescia runtime.
Stare sciezki i nazwy sa utrzymywane tylko w archiwach i raportach audytu.

## Mapa procesu

| Etap | Wejscie glówne | Wyjscie glówne | Liczba plików |
|---|---|---|---|
| `sonar_market` | `SONAR_TOKEN`, lista projektow | `artifacts/sources/sonar_market/timeseries/`, `artifacts/products_light/sonar_market/*` | `N projektow` |
| `github_market` | `GITHUB_TOKEN`, lista repo | `artifacts/sources/github_market/per_repo/`, `artifacts/sources/github_market/repo_selection_v01.*`, `artifacts/products_light/github_market/*` | `N repozytoriow` |
| `github_pr_flow` | `GITHUB_TOKEN`, `mpieniak01/Venom` | `artifacts/sources/pr_flow/per_repo/`, `artifacts/products_light/pr_flow/*` | `1 komplet` |
| `github_pr_comments` | `GITHUB_TOKEN`, `mpieniak01/Venom` | `artifacts/products_light/pr_comments/*` | `1 komplet` |
| `visualization_sources_pack` | agregaty + layout CSV | `artifacts/processing/visualization/sources_pack_v01.*` | `1 pack` |
| `visualization_summary_tables` | sources pack + chart spec + style/control profile | `artifacts/processing/visualization/summary_tables_v04.csv` | `1 tabela` |
| `visualization_pipeline` | pack + summary + layout + map | `_external/not_tracked/visualization/*.docx|xlsx`, `artifacts/products_light/visualization/*` | `1 workbook + 1 docx` |


## Makefile

`Makefile` jest preferowanym interfejsem uruchamiania dla ludzi i agentow AI. Najpierw sprawdz:

```bash
make help
```

Podstawowe targety:

- `make test-contracts` - testy kontraktow logiki skryptow, bez API i bez Office.
- `make test-contracts-ci` - kontrakt CI: sample inputy + testy + static + parse.
- `make test-contracts-local-real` (wymaga prywatnego local config) - kontrakt local-real: `v04` ma wskazywac na realne listy kluczy.
- `make test-data-local` - lokalne testy jakosci aktualnych artefaktow, poza CI.
- `CONFIRM_API=1 make fetch-*` - jawne pobieranie danych z API.
- `make process` - S01+S02 z istniejacych artefaktow, bez sieci.
- `make product-excel-only` - generowanie Excela przez Windows Office COM, bez pobierania danych.

Separacja jest celowa: kroki API sa kosztowne i nie moga byc uruchamiane przypadkowo przez agentow ani CI.

## Python

### `tools/path_config.py`
- Po co: wspolny resolver configu i sciezek dla wszystkich skryptow.
- Kiedy uruchamiac: nie uruchamiamy bezposrednio; importowany przez tools.
- Wejscia: centralny config.
- Wyjscia: brak, helper runtime.

### `tools/sonar_market_benchmark.py`
- Po co: pobranie benchmarku Sonar (snapshot/timeseries).
- Kiedy uruchamiac: domena `sonar_market`.
- Wejscia: `SONAR_TOKEN`, `artifacts/inputs/sonar_market/project_keys_selected_v01.txt`.
- Tryb testowy: `artifacts/inputs/sonar_market/project_keys_selected_v01.txt` przez `config/process_pipeline_v04_test.json`.
- Wyjscia:
  - `artifacts/sources/sonar_market/timeseries/` (per-project),
  - `artifacts/products_light/sonar_market/timeseries_agg_2026_v01.csv`,
  - `artifacts/products_light/sonar_market/benchmark_analysis_2026_v01.json|md`.
- Przyklad:
```bash
python3 tools/sonar_market_benchmark.py --mode timeseries --dataset-id sonar_market --config config/process_pipeline_v01.json
```

### `tools/github_market_benchmark.py`
- Po co: discovery i analiza repo GitHub do benchmarku rynku.
- Kiedy uruchamiac: domena `github_market`.
- Wejscia: `GITHUB_TOKEN` albo `gh auth token`, opcjonalnie `repo-file`.
- Tryb testowy: `artifacts/inputs/github_market/repo_keys_selected_v01.txt` przez `config/process_pipeline_v04_test.json`.
- Wyjscia:
  - `artifacts/sources/github_market/per_repo/`,
  - `artifacts/sources/github_market/repo_selection_v01.json|md`,
  - `artifacts/products_light/github_market/timeseries_agg_2026_v01.csv`,
  - `artifacts/products_light/github_market/benchmark_analysis_2026_v01.json|md`.
- Przyklad:
```bash
python3 tools/github_market_benchmark.py --mode analyze --dataset-id github_market --config config/process_pipeline_v04.json --max-commits-per-repo 0
```

### `tools/github_pr_flow.py`
- Po co: dzienne metryki PR flow (opened/merged/active).
- Kiedy uruchamiac: domena `pr_flow`.
- Wejscia: `GITHUB_TOKEN`, owner/repo.
- Wyjscia:
  - `artifacts/sources/pr_flow/per_repo/raw|csv`,
  - `artifacts/products_light/pr_flow/timeseries_agg_2026_v01.csv`,
  - `artifacts/products_light/pr_flow/analysis_2026_v01.json|md`.
- Lokalna historia git nie jest zrodlem aktywnego pipeline v4; PR flow jest pobierany przez GitHub API.
- Przyklad:
```bash
python3 tools/github_pr_flow.py --dataset-id github_pr_flow --config config/process_pipeline_v01.json --owner mpieniak01 --repo Venom
```

### `tools/github_closed_pr_analysis.py`
- Po co: analiza zamknietych PR (churn, komentarze, rozklady).
- Kiedy uruchamiac: domena `pr_comments`.
- Wejscia: GitHub API (`gh auth` lub `GITHUB_TOKEN`).
- Wyjscia:
  - `artifacts/products_light/pr_comments/analysis_2026_v01.json|md`.
- Przyklad:
```bash
python3 tools/github_closed_pr_analysis.py --dataset-id github_pr_comments --config config/process_pipeline_v01.json --owner mpieniak01 --repo Venom
```

### `tools/prepare_sources.py`
- Po co: standaryzacja i zlozenie zrodel do workbook pipeline.
- Kiedy uruchamiac: S01 (domena `visualization`).
- Wejscia: agregaty z `sonar_market/github_market/pr_flow/pr_comments` + layout CSV.
- Kontrakt v3: `github_market` musi zawierac `mpieniak01/Venom` w 205C; brak tego repo jest bledem wejscia, a nie powodem do lokalnego fallbacku.
- Wyjscia: `artifacts/processing/visualization/sources_pack_v01.json|csv`.
- Przyklad:
```bash
python3 tools/prepare_sources.py --dataset-id visualization_sources_pack --config config/process_pipeline_v04.json
```

### `tools/build_summary_tables.py`
- Po co: budowa tabel summary pod wykresy.
- Kiedy uruchamiac: S02 (domena `visualization`).
- Wejscia: `sources_pack` + `chart_spec` + `chart_style_profile`.
-- Wyjscia: `artifacts/processing/visualization/summary_tables_v04.csv` z dodatkowa kontrola source-series health.
- Przyklad:
```bash
python3 tools/build_summary_tables.py --dataset-id visualization_summary_tables --config config/process_pipeline_v04.json
```

### `tools/template_chart_audit.py`
- Po co: lekki audyt szablonu `.xlsx` i porownanie go ze specyfikacja chartow.
-- Kiedy uruchamiac: po zmianach `chart_spec_v04.json` albo przed publikacja workbooka.
-- Wejscia: szablon Excela + `chart_spec_v04.json`.
-- Wyjscia: `artifacts/products_light/visualization/template_chart_audit_v04.md|json`.
- Przyklad:
```bash
python3 tools/template_chart_audit.py --template artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx --chart-spec artifacts/inputs/visualization/chart_spec_v04.json --out-md artifacts/products_light/visualization/template_chart_audit_v04.md --out-json artifacts/products_light/visualization/template_chart_audit_v04.json
```

### `artifacts/template/04_przygotuj_arkusze_wykresow.mjs`
- Status: legacy reference, nieaktywny generator.
- Po co istnieje: historyczny skrypt budujący workbook przez `@oai/artifact-tool` z dwóch CSV.
- Nie używać jako części aktywnego pipeline, bo omija `chart_spec_v04.json`, walidację, PR flow, kontrakt faz i aktualne źródła API.
- Co można z niego brać: inspiracje dla narracji arkuszy, tytułów, kolorów domen, wyróżnienia Venom i arkusza metryk.
- Szczegółowa analiza: `docs/LEGACY_TEMPLATE_MJS_REVIEW.md`.

## Helpers

### `tools/report_alias_coverage.py`
- Po co: audyt, czy w aktywnym procesie nie zostaly stare referencje robocze.
- Kiedy uruchamiac: po zmianach configu i przed publikacja paczki.
- Wejscia: `config/process_pipeline_v01.json`.
- Wyjscia: `artifacts/meta/legacy_reference_audit_v01.json|md`.
- Przyklad:
```bash
python3 tools/report_alias_coverage.py --config config/process_pipeline_v01.json
```

### `tools/verify_input_mode_contract.py`
- Po co: twarda walidacja kontraktu `real vs sample` dla list kluczy wejściowych.
- Kiedy uruchamiac:
  - CI: `--mode ci` (sample w `v04_test`, real w `v04`),
  - lokalnie: `--mode local-real` (wymuszenie realnych list w `v04`).
- Wejscia: `config/process_pipeline_v04.json`, `config/process_pipeline_v04_test.json`.
- Wyjscia: status `0/!=0` (gate pass/fail).
- Przyklad:
```bash
python3 tools/verify_input_mode_contract.py --mode ci
python3 tools/verify_input_mode_contract.py --mode local-real
```

### `tools/export_research_pack.py`
- Po co: export whitelisty do recenzji/publikacji.
- Kiedy uruchamiac: przygotowanie paczki.
- Wejscia: config + profil exportu (`profiles.export`, fallback `export_profiles`).
- Wyjscia: lista/pliki eksportowe + raport export.
- Przyklad:
```bash
python3 tools/export_research_pack.py --config config/process_pipeline_v01.json --profile scripts_review --dry-run
```

## PowerShell (Office COM)

### `tools/excel_build_workbook.ps1`
- Po co: budowa workbook na podstawie `sources_pack + summary + layout`; arkusze moga laczyc dane i wykres obok siebie.
- Kiedy uruchamiac: S03.
- Wejscia: `artifacts/processing/visualization/sources_pack_v01.json`, `artifacts/processing/visualization/summary_tables_v04.csv`, `artifacts/inputs/visualization/workbook_layout_v04.json`.
- Wyjscia: `_external/not_tracked/visualization/workbook_v04.xlsx`.

### `tools/excel_add_charts.ps1`
- Po co: generowanie wykresow na arkuszach wskazanych w specyfikacji workbooka.
- Kiedy uruchamiac: S04.
- Wejscia: workbook + `artifacts/inputs/visualization/chart_spec_v04.json` + profil stylu.
- Wyjscia: zaktualizowany workbook.

### `tools/excel_apply_advanced_patterns.ps1`
- Po co: dodanie elementow narracyjnych typu B.
- Kiedy uruchamiac: S05.
- Wejscia: workbook + chart spec + `docs/EXCEL_ADVANCED_PATTERNS.md`.
- Wyjscia: zaktualizowany workbook + metadane na arkuszu `meta`.

### `tools/office_hygiene.ps1`
- Po co: czyszczenie wiszacych instancji `WINWORD.EXE` i `EXCEL.EXE` uruchomionych przez automatyzacje.
- Kiedy uruchamiac: preflight i postflight w `tools/run_pipeline.ps1`.
- Wejscia: brak.
- Wyjscia: log z liczba ubitych procesow Office automation.

### `tools/word_create_embed_canvas.ps1`
- Po co: utworzenie pustego dokumentu Word z bookmarkami.
- Kiedy uruchamiac: pomocniczo przed embed.
- Wejscia: `artifacts/inputs/visualization/word_embed_map_v04.csv`.
- Wyjscia: `_external/not_tracked/visualization/embed_canvas_v04.docx`.

### `tools/word_insert_bookmarks.ps1`
- Po co: uzupelnienie bookmarkow w dokumencie bazowym.
- Kiedy uruchamiac: S06.
- Wejscia: input docx + mapa.
- Wyjscia: output docx (z bookmarkami).

### `tools/word_embed_charts.ps1`
- Po co: osadzenie wykresow Excel jako obrazow do bookmarkow Word.
- Kiedy uruchamiac: S07.
- Wejscia: workbook + input docx + mapa.
- Wyjscia:
  - output docx,
  - `artifacts/products_light/visualization/word_embed_run_v04.json|md`.

### `tools/verify_excel_product.ps1`
- Po co: walidacja workbooka i serii; sprawdza rowniez pustośc, rzadkosc i brak kolumn zrodlowych.
- Kiedy uruchamiac: S08.
- Wejscia: workbook + chart spec.
- Wyjscia: `artifacts/products_light/visualization/excel_verify_v04.json|md`.

### `tools/verify_word_embeddings.ps1`
- Po co: walidacja mapowania bookmark <-> osadzenia wykresow.
- Kiedy uruchamiac: S09.
- Wejscia: output docx + mapa + raport S07.
- Wyjscia: `artifacts/products_light/visualization/word_embed_verify_v04.json|md`.

### `tools/run_pipeline.ps1`
- Po co: orkiestracja S01-S10 jednym poleceniem.
- Kiedy uruchamiac: end-to-end przebieg pipeline.
- Wejscia: `-ConfigPath config/process_pipeline_v04.json`.
- Wyjscia: `artifacts/products_light/visualization/pipeline_run_v04.json|md`.
- Log procesu: `artifacts/log/*.log`, jeden plik na przebieg, linie start/stop per krok, bez detali rekordowych.
- Indeks przebiegow: `artifacts/log/manifest.json|md`, aktualizowany po kazdym uruchomieniu.

Przyklad:
```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath config/process_pipeline_v04.json
```

## Runtime

- Empiryczne zakresy czasow krokow: `docs/PIPELINE_RUNTIME_BANDS.md`.

## V3 scaffold

Warstwa `v04` dodaje kontrakt sterowania wykresami:

- `artifacts/inputs/visualization/chart_control_profile_v04.json`
- `artifacts/inputs/visualization/chart_spec_v04.json`
- `artifacts/inputs/visualization/chart_style_profile_v04.json`
- `artifacts/inputs/visualization/workbook_layout_v04.json`
- `config/process_pipeline_v04.json`

To jest baza pod wykresy mieszane, serii pomocnicze i osi sekundarne. Nie zmienia jeszcze danych wejściowych.
