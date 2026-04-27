# 205F Plan Skryptow Automatyzacji v01

Data: `2026-04-27`  
Tryb: plan implementacyjny (bez kodowania na tym etapie)

## 1. Stan obecny (as-is)

W `tools/` mamy komplet skryptów ETL do pozyskania danych:
1. `sonar_market_benchmark.py` -> seria 205B
2. `205C_github_market_benchmark_q1.py` -> seria 205C
3. `205D_github_pr_flow_q1.py` -> seria 205D
4. `205E_github_closed_pr_analysis.py` -> seria 205E

Status operacyjny dla istniejących skryptów GitHub (205C/205D/205E):
- skrypty zostały użyte (`executed`),
- wygenerowały niepuste artefakty wynikowe (`non_empty`),
- nie zakładamy, że przeszły pełne testy poprawności merytorycznej wyników (`result_validation=not_tested`).

Status implementacyjny 205F:
- `S01-S02`: zaimplementowane i uruchomione (artefakty `v01` wygenerowane),
- `S03-S05` + `S08`: ponownie uruchomione w pipeline (`S10 -SkipWord`), smoke-check przechodzi (`charts_ok: 7/7`),
- `S06-S07-S09`: działają, ale `S06` wymaga nieblokowanego pliku wejściowego `docx` (otwarty dokument w Word potrafi zablokować krok),
- `S07`: ustabilizowany przez staging lokalny Windows (`C:\temp\...`) + telemetryczny raport per chart,
- `S09`: dopięty do raportu `S07`, final status `ok` gdy `embedded_in_bookmark_range == mapped_active` i `s07_failed_count == 0`.
- `S10`: ma tryb nadzorczy (`-StepTimeoutSec`, `-CleanupOfficeOrphans`) do fail-fast i sprzątania osieroconych procesów Office między krokami.

Brakująca warstwa do zbudowania:
- konsolidacja danych pod Excel,
- budowa workbooka z zakładkami i wykresami,
- osadzanie wykresów do Word przez mapę `chart_id -> bookmark`,
- kontrola poprawności wykonania (nie testy jednostkowe, tylko kontrola produktu).

## 2. Architektura kolejnych faz

1. Faza A - `prepare` (przetworzenie źródeł)
2. Faza B - `excel-build` (skoroszyt + wykresy)
3. Faza C - `word-embed` (osadzenie do DOCX)
4. Faza D - `verify` (kontrola artefaktów i mapowania)

## 3. Docelowe skrypty (propozycja)

## 3A. Przetworzenie danych

1. `tools/205f_prepare_sources.py`
- Cel: zbudować zestandaryzowane tabele `src_*` i `wrk_*`.
- Wejście:
  - `205B/timeseries/205B_timeseries_q1_2026.csv`
  - `205C/timeseries/205C_github_benchmark_q1_2026.csv`
  - `205D/timeseries/205D_pr_flow_q1_2026.csv`
  - `205E/timeseries/csv/205E_pr_comments_q1_2026_daily.csv`
  - `205F/inputs/205F_excel_sheet_layout_v01.csv`
- Wyjście:
  - `produkty/meta/205F_sources_pack_vNN.json`
  - `produkty/meta/205F_sources_pack_vNN.csv`
- Kontrola sukcesu:
  - wszystkie wymagane kolumny obecne,
  - zakres dat Q1 2026 zachowany,
  - brak duplikatów `(project_key,date)` w tabelach dziennych.

2. `tools/205f_build_summary_tables.py`
- Cel: policzyć tabele `summary` i agregaty benchmarkowe.
- Wejście: `205F_sources_pack_vNN.*`
- Wyjście: `produkty/meta/205F_summary_tables_vNN.csv`
- Kontrola sukcesu:
  - każda metryka ma zdefiniowaną formułę agregacji,
  - `chart_id` z `205F_chart_spec_v01.json` ma źródło w tabelach.

## 3B. Budowa Excela

3. `tools/205f_excel_build_workbook.ps1` (COM Excel)
- Cel: zbudować `xlsx` z kartami wg layoutu i wgrać dane.
- Wejście:
  - `205F_excel_sheet_layout_v01.csv`
  - `205F_sources_pack_vNN.*`
  - `205F_summary_tables_vNN.csv`
- Wyjście:
  - `produkty/excel/workspace/205F_visualization_workspace_vNN.xlsx`
- Kontrola sukcesu:
  - wszystkie wymagane zakładki istnieją,
  - nagłówki tabel zgodne ze specyfikacją,
  - plik otwieralny w Excel bez błędów.

4. `tools/205f_excel_add_charts.ps1` (COM Excel)
- Cel: utworzyć wykresy wg `205F_chart_spec_v01.json`.
- Wejście:
  - `205F_visualization_workspace_vNN.xlsx`
  - `205F_chart_spec_v01.json`
- Wyjście:
  - ten sam `xlsx` z obiektami wykresów nazwanymi `chart_id`
- Kontrola sukcesu:
  - liczba wykresów == liczba pozycji w spec,
  - każdy wykres ma poprawny `chart.Name == chart_id`,
  - osie i serie nie są puste.

5. `tools/205f_excel_apply_advanced_patterns.ps1` (COM Excel)
- Cel: dodać warstwę opisową dla Typu B.
- Wejście:
  - `205F_excel_advanced_patterns_v01.md`
  - `205F_chart_spec_v01.json`
- Wyjście:
  - `205F_visualization_workspace_vNN.xlsx` z elementami narracyjnymi
- Kontrola sukcesu:
  - dla wykresów Typu B obecne `background_series/label_series/reference_lines/annotation_shapes`.

## 3C. Osadzanie do Word

6. `tools/205f_word_insert_bookmarks.ps1` (opcjonalny)
- Cel: utworzyć brakujące bookmarki `BM_<chart_id>` w dokumencie Word.
- Wejście:
  - `205F_word_embed_map_v01.csv`
  - `produkty/word/final/*.docx`
- Wyjście:
  - nowa wersja DOCX `_vNN`
- Kontrola sukcesu:
  - każdy `word_bookmark` z mapy istnieje.

7. `tools/205f_word_embed_charts.ps1` (COM Word + Excel)
- Cel: osadzić wykresy z Excela do Word po mapie.
- Wejście:
  - `205F_visualization_workspace_vNN.xlsx`
  - `205F_word_embed_map_v01.csv`
  - `produkty/word/final/*.docx`
- Wyjście:
  - `produkty/word/final/*_vNN.docx`
- Kontrola sukcesu:
  - każdy wpis mapy ma status `embedded`,
  - liczba osadzonych obiektów == liczba rekordów `active/planned`.

## 3D. Kontrola poprawnosci (produktowa)

8. `tools/205f_verify_excel_product.ps1`
- Cel: kontrola integralności workbooka.
- Wejście: `205F_visualization_workspace_vNN.xlsx`
- Raport:
  - `205F/analysis/205F_excel_verify_vNN.json`
  - `205F/analysis/205F_excel_verify_vNN.md`
- Checks:
  - lista zakładek,
  - lista wykresów i ich `chart_id`,
  - niepuste serie danych,
  - zgodność ze spec.

9. `tools/205f_verify_word_embeddings.ps1`
- Cel: kontrola mapowania Word.
- Wejście: `*_vNN.docx`, `205F_word_embed_map_v01.csv`
- Raport:
  - `205F/analysis/205F_word_embed_verify_vNN.json`
  - `205F/analysis/205F_word_embed_verify_vNN.md`
- Checks:
  - bookmark istnieje,
  - obiekt osadzony przy bookmarku,
  - zgodność `chart_id` -> podpis/caption.

10. `tools/205f_run_pipeline.ps1`
- Cel: orchestrator faz A-D.
- Wejście: wersje wejściowe `_vNN`.
- Wyjście: produkty `_vNN` + raport wykonania.
- Kontrola sukcesu:
  - status per krok,
  - lista artefaktów końcowych,
  - brak kroków `failed`.

## 4. Priorytet wdrożenia

1. `205f_excel_build_workbook.ps1`
2. `205f_excel_add_charts.ps1`
3. `205f_verify_excel_product.ps1`
4. `205f_word_embed_charts.ps1`
5. `205f_verify_word_embeddings.ps1`
6. pozostałe skrypty wspierające

## 5. Gotowość wiedzy

Stan wiedzy jest kompletny do rozpoczęcia implementacji:
1. znamy źródła wejściowe,
2. mamy spec wykresów i mapę Excel->Word,
3. mamy reguły wersjonowania `_vNN`,
4. mamy potwierdzone technicznie COM Excel/Word z WSL.

Brakujące elementy przed kodowaniem:
- decyzja o pierwszym numerze wersji roboczej (`v01` czy `v02` dla workspace),
- decyzja czy bookmarki będą tworzone automatycznie czy ręcznie.
