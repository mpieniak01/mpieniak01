# Excel Advanced Patterns

Dokument opisuje dodatkowe wzorce narracyjne dla wykresów Excela używane przez `excel_apply_advanced_patterns.ps1`.

## Cel

Podstawowe wykresy pokazują serie danych. Wzorce zaawansowane dodają kontekst interpretacyjny: tło, etykiety, linie odniesienia, adnotacje albo metadane.

Ten krok nie jest źródłem danych. Dane i serie wykresów wynikają ze specyfikacji chartów oraz workbooka.

Od `v04` workbook wspiera też tryb `sheet_synthesis`: wykres zbiorczy dla arkusza z wieloma wykresami szczegółowymi. Ten wykres jest renderowany jako pierwszy na danej zakładce, a pozostałe wykresy są automatycznie przesuwane niżej w stałym kroku layoutu.

## Zakres

- `background_series` - serie lub obszary tła,
- `label_series` - serie etykietujące,
- `reference_lines` - linie odniesienia,
- `annotation_shapes` - adnotacje i kształty,
- arkusz `meta` - metadane dodane po wygenerowaniu workbooka.

## Kontrakt

- źródłem prawdy dla wykresów jest `artifacts/inputs/visualization/chart_spec_v04.json`,
- źródłem prawdy dla arkuszy i pozycjonowania jest `artifacts/inputs/visualization/workbook_layout_v04.json`,
- źródłem prawdy dla wyglądu jest `artifacts/inputs/visualization/chart_style_profile_v04.json`,
- kontrakt v4 dla sterowania seriami, osiami i trybami wykresów jest w `artifacts/inputs/visualization/chart_control_profile_v04.json` oraz `artifacts/inputs/visualization/chart_spec_v04.json`,
- kontrakt stabilności v4, w tym formaty dat, liczby projektów, `source_type`, fazy i zakazy regresji, jest w `docs/VISUALIZATION_V4_STABILITY_CONTRACT.md`,
- brak elementów zaawansowanych nie powoduje błędu kroku,
- skrypt nie powinien zmieniać danych źródłowych ani agregacji.

## Zasada interpretacji

Jeżeli wykres ma dodatkową adnotację lub linię odniesienia, należy traktować ją jako warstwę narracyjną. Wartości liczbowe nadal należy weryfikować w tabeli arkusza i w raporcie walidacji workbooka.
