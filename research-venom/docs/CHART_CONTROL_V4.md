# CHART CONTROL V4

`v04` jest kolejnym kontraktem wizualizacji dla `research-venom`.

## Zakres

`v04` zachowuje bazowy układ 17 arkuszy i 21 wykresów z szablonu `artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx`, ale rozwija go o:

1. legacy-inspired styling arkuszy,
2. `analysis_caption` dla chartów syntetycznych,
3. `synthetic_combo` jako jawny tryb wykresu,
4. wyróżnienie `mpieniak01/Venom` w chartach porównawczych,
5. osobny kontrakt plików i raportów `v04`.

## Pliki kontraktu

- `config/process_pipeline_v04.json`
- `artifacts/inputs/visualization/chart_spec_v04.json`
- `artifacts/inputs/visualization/workbook_layout_v04.json`
- `artifacts/inputs/visualization/chart_style_profile_v04.json`
- `artifacts/inputs/visualization/chart_control_profile_v04.json`
- `artifacts/inputs/visualization/word_embed_map_v04.csv`
- `docs/VISUALIZATION_V4_STABILITY_CONTRACT.md`

## Zasady

1. `phase_*` nadal renderują tło faz na osi pomocniczej.
2. `analysis_caption` jest obowiązkowe dla chartów `synthetic_combo`.
3. Charty porównawcze pokazują pełne klucze projektów, bez skracania do `inne`.
4. `v04` nie zmienia metodyki pobierania danych.
5. `v04` może współistnieć z `v03` tylko jako archiwalny punkt odniesienia, ale aktywny pipeline używa wyłącznie `v04`.
6. `WP1`-`WP4` pokazują pełne 11 repozytoriów z `src_205D_timeseries`, a nie podzbiór peerów.
7. `source_type` arkusza musi odpowiadać domenie danych: `github`, `sonarqube` albo `git_prflow`.
8. Daty w tabelach workbooka są datami Excela w formacie `dd.mm.yyyy`; skrót `mm-dd` jest tylko dla osi wykresów.
9. Wiersze 1 i 2 arkusza nie są scalane, nie są zawijane i nie determinują szerokości kolumn danych.
10. Kolory domenowe pochodzą z `source_type_palette`; nie wolno mieszać ich z kolorami faz.

## Reguły Antyregresyjne

Szczegółowy kontrakt stabilności jest w [VISUALIZATION_V4_STABILITY_CONTRACT](VISUALIZATION_V4_STABILITY_CONTRACT.md).

Najważniejsze blokady regresji:

1. `comparison_peer_group_size` w aktywnym `v04` pozostaje `11`, jeśli nie zmienia się metodologia badania.
2. `WP6_Venom_Lead_Time` pozostaje wykresem zdarzeniowym/kolumnowym dla sparse lead time, a nie linią trendu.
3. Serie `phase_*` są tłem na osi pomocniczej `0..100` i nie zmieniają skali osi głównej.
4. `W32_LOC` i `W33_Dzienny_Przeplyw` są domeną `github`.
5. `WP5_Venom_PR_Daily` i `WP6_Venom_Lead_Time` są domeną `git_prflow`.
6. Charty porównawcze nie mogą ukrywać pełnych kluczy projektów ani zastępować ich grupą `inne`.

## Główne charty syntetyczne

- `C_W37_DEBT_03`
- `C_W37_ISSUES_03`
- `C_W35_ISSUES_03`
- `C_W35_COVERAGE_03`
- `C_W35_UNIT_TESTS_03`
- `C_W42_ISSUES_03`
- `C_W42_LOC_03`
- `C_W42_UNIT_TESTS_03`
- `C_W43_DEBT_03`
- `C_WP5_PR_DAILY_03`
- `C_WP6_LEAD_TIME_DAILY_03`

## Walidacja

`v04` jest poprawne, jeśli:

1. `make test` przechodzi,
2. `make audit-template-v4` pokazuje `21` chartów w template i `21` chartów w spec,
3. `make product-excel-v4` kończy się bez błędów,
4. `excel_verify_v04` ma `charts_failed: 0`,
5. `WP1`-`WP4` mają `rendered_project_count: 11`,
6. aktywne `source_type` przechodzą test kontraktowy.
