# Legacy MJS Template Generator Review

Data analizy: `2026-04-30`

Analizowany plik:

- `artifacts/template/04_przygotuj_arkusze_wykresow.mjs`

Aktualny pipeline referencyjny:

- `config/process_pipeline_v04.json`
- `tools/prepare_sources.py`
- `tools/build_summary_tables.py`
- `tools/excel_build_workbook.ps1`
- `tools/excel_add_charts.ps1`
- `tools/verify_excel_product.ps1`
- `artifacts/inputs/visualization/chart_spec_v04.json`
- `artifacts/inputs/visualization/chart_style_profile_v04.json`
- `artifacts/inputs/visualization/chart_control_profile_v04.json`
- `docs/VISUALIZATION_V4_STABILITY_CONTRACT.md`

## 1. Status Skryptu

`04_przygotuj_arkusze_wykresow.mjs` jest historycznym generatorem workbooka, a nie aktywnym elementem pipeline v4.

Nie powinien być uruchamiany jako zamiennik obecnego procesu, bo:

1. bierze dane bezpośrednio z `artifacts/02_dane_surowe`,
2. obsługuje tylko dwa źródła CSV:
   - `06_205B_timeseries_q1_2026.csv`,
   - `07_205C_github_benchmark_q1_2026.csv`,
3. nie obsługuje aktualnych źródeł PR flow i PR comments,
4. nie ma kontraktu `chart_spec_v04.json`,
5. nie ma walidacji workbooka,
6. nie ma kontraktu faz, osi pomocniczych, aktywnych faz ani zakresu osi dat,
7. używa twardych zakresów komórek, np. `A4:G994`, `A106:C196`,
8. generuje inny skoroszyt wynikowy:
   - `artifacts/08_praca_koncowa/AI_wykresy_i_tabele_robocze_2026-04-25_alfa.xlsx`.

## 2. Różnica Architektury

| Obszar | Legacy MJS | Pipeline v4 |
|---|---|---|
| Silnik | `@oai/artifact-tool` | Python + PowerShell + Excel COM |
| Wejścia | 2 pliki CSV | źródła API, sources pack, summary tables |
| Definicja chartów | kod proceduralny | `chart_spec_v04.json` |
| Styl | funkcje JS w skrypcie | `chart_style_profile_v04.json` |
| Sterowanie typem serii | lokalne helpery `addBarChart` / `addLineChart` | `series_plan`, `metric_semantics`, `phase_scope_mode` |
| Fazy | brak globalnego kontraktu faz | `chart_control_profile_v04.json` + walidacja |
| Walidacja | brak | `verify_excel_product.ps1` + testy |
| Zakres dat | twarde zakresy komórek | `x_axis_scope_mode`, `x_axis_start`, `x_axis_end` |
| Word | poza zakresem | pipeline może osadzać wykresy w Wordzie |

## 3. Co Warto Z Niego Zachować

Legacy skrypt nie powinien być źródłem danych ani generatorem v4, ale zawiera użyteczne decyzje prezentacyjne.

### 3.1 Narracja Arkuszy

Skrypt dobrze rozdziela arkusze na:

1. opis workbooka,
2. definicje metryk,
3. dane surowe,
4. benchmark jakości,
5. benchmark aktywności,
6. Venom jako przebieg jakości,
7. Venom jako przebieg aktywności.

To podejście jest spójne z naszym aktualnym modelem:

1. tabela jako źródło weryfikacji,
2. wykres jako szybki obraz,
3. opis jako kontekst biznesowy.

Wniosek: warto zachować tę narrację w dokumentacji i opisach arkuszy, ale generować ją przez obecny pipeline.

### 3.2 Styl Nagłówków i Tabel

Przydatne elementy:

1. tytuł arkusza w ciemnym pasku:
   - `#0F172A`,
   - biały tekst,
   - bold,
   - rozmiar `14`,
2. opis pod tytułem:
   - `#E2E8F0`,
   - italic,
   - wrap text,
3. nagłówki tabel:
   - jakość: `#0F766E`,
   - aktywność: `#7C3AED`,
   - ogólne benchmarki: `#1E3A8A`,
4. banded rows w tabelach,
5. zamrożenie nagłówków,
6. czytelne szerokości kolumn.

Aktualny v3 używa bardziej jednolitego niebieskiego profilu:

- tytuł chartu: `#1F5FA8`,
- legenda: `#0D3B73`,
- tło plot area: `#F4F8FC`,
- paleta serii: `#1F5FA8`, `#6EA8DC`, `#0D3B73`, `#9DC3E6`.

Wniosek: nie przenosić kolorów 1:1 do chartów v3, ale rozważyć przeniesienie rozróżnienia domen arkuszy:

1. Sonar/jakość jako teal,
2. GitHub/aktywność jako violet,
3. wspólne benchmarki jako navy.

To wymagałoby osobnego PR, bo aktualny styl v3 celowo jest template-blue.

### 3.3 Venom Highlight

Legacy skrypt wyróżnia Venom w tabelach:

- jakość: `#FDE68A`,
- aktywność: `#EDE9FE`,
- w benchmarkach aktywności tworzy pomocnicze serie:
  - `Projekt Venom`,
  - `Projekty kontekstowe`.

To jest wartościowy wzorzec prezentacyjny.

Aktualny v3 rozwiązuje problem merytorycznie przez:

1. `Venom anchor`,
2. deterministyczną peer group,
3. pełne klucze projektów,
4. walidację obecności Venom.

Wniosek: można w przyszłości dodać wizualne wyróżnienie Venom w chartach porównawczych, ale nie poprzez ręczne helper tables w kodzie. Powinno to być pole w konfiguracji, np.:

```json
{
  "highlight_project_key": "mpieniak01/Venom",
  "highlight_series_color_rgb": "1D4ED8",
  "peer_series_color_rgb": "BFDBFE"
}
```

### 3.4 Helper Tables

Skrypt generuje pomocnicze tabele do wykresów, np. start/end dla jakości albo rozdzielenie Venom vs kontekst.

To jest koncepcyjnie dobre, bo:

1. wykres ma prosty zakres danych,
2. tabela źródłowa wykresu jest czytelna,
3. łatwo sprawdzić, skąd wzięły się serie.

Aktualny pipeline v4 robi to w sposób bardziej kontrolowany przez:

1. `prepare_sources.py`,
2. `build_summary_tables.py`,
3. `chart_spec_v04.json`,
4. `workbook_layout_v04.json`.

Wniosek: helper tables są już częścią aktualnego podejścia, ale powinny powstawać w Pythonie i być testowane, nie generowane ad hoc w `.mjs`.

### 3.5 Opisy Metryk

Arkusz `Metryki` w legacy skrypcie zawiera prosty słownik:

1. commit,
2. LOC,
3. dodania,
4. usunięcia,
5. churn,
6. issues,
7. dług techniczny,
8. pokrycie testami,
9. testy jednostkowe,
10. dni aktywne.

Wniosek: warto utrzymać analogiczną warstwę opisową w dokumentacji albo workbooku. Aktualnie część tej roli pełnią:

1. `docs/RESEARCH_MODEL.md`,
2. `docs/PROCESS_DATA_MAP.md`,
3. opisy `sheet_description` i `table_description`.

## 4. Czego Nie Przenosić

Nie przenosić:

1. bezpośredniego parsowania CSV przez `parseCsv`, bo nie obsługuje pełnego CSV i nie ma walidacji,
2. twardych zakresów komórek,
3. generowania workbooka poza `run_pipeline.ps1`,
4. proceduralnych definicji chartów w JS,
5. ręcznie kodowanych list etykiet jako źródła prawdy,
6. liniowych wykresów dla zdarzeń, np. aktywności dziennej, bez semantyki metryki,
7. braku walidacji po wygenerowaniu workbooka.

## 5. Porównanie Podejścia Do Wykresów

Legacy:

1. `addBarChart(sheet, range, title, fromCell, toCell)`,
2. `addLineChart(sheet, range, title, fromCell, toCell, legend)`,
3. chart type wynika z helpera wywołanego w kodzie,
4. brak formalnego kontraktu osi i serii.

v4:

1. `chart_spec_v04.json` definiuje chart ID, arkusz, źródło, serie, typy i semantykę,
2. `chart_control_profile_v04.json` definiuje fazy, oś dat, walidację i tryby,
3. `excel_add_charts.ps1` generuje wykresy z konfiguracji,
4. `verify_excel_product.ps1` sprawdza gotowy workbook.

Wniosek: obecne podejście jest lepsze dla pracy z agentami AI, bo logika jest jawna, testowalna i mniej zależna od lokalnych decyzji proceduralnych.

## 6. Rekomendacje

### 6.1 Do Zachowania Jako Inspiracja

1. styl tytuł + subtitle na każdym arkuszu,
2. domenowe kolory arkuszy,
3. jawny arkusz słownika metryk,
4. wizualne wyróżnienie Venom w tabelach i benchmarkach,
5. helper tables jako czytelne źródło wykresu,
6. krótkie komentarze biznesowe przy metrykach.

### 6.2 Do Wdrożenia Tylko Przez Nowy PR

Jeśli będziemy przenosić inspiracje, powinien powstać osobny PR, np.:

`211A_pr_visualization_worksheet_narrative_and_venom_highlight.md`

Zakres takiego PR:

1. dodać konfigurowalne kolory domen arkuszy,
2. dodać opcjonalne wyróżnienie Venom w tabelach porównawczych,
3. rozważyć arkusz `Metryki` albo sekcję definicji metryk w workbooku,
4. nie zmieniać metodologii danych,
5. nie zastępować `chart_spec_v04.json` proceduralnym JS.

### 6.3 Decyzja Architektoniczna

`04_przygotuj_arkusze_wykresow.mjs` pozostaje artefaktem historycznym.

Aktywnym źródłem prawdy pozostają:

1. `config/process_pipeline_v04.json`,
2. `artifacts/inputs/visualization/chart_spec_v04.json`,
3. `artifacts/inputs/visualization/workbook_layout_v04.json`,
4. `artifacts/inputs/visualization/chart_style_profile_v04.json`,
5. `artifacts/inputs/visualization/chart_control_profile_v04.json`,
6. testy w `tests/`,
7. walidatory w `tools/`.

## 7. Krótka Konkluzja

Ze skryptu legacy możemy wyciągnąć inspiracje stylistyczne i narracyjne, ale nie logikę produkcyjną.

Najbardziej wartościowe elementy:

1. arkusz definicji metryk,
2. lepsza narracja tytuł + subtitle,
3. wyróżnienie Venom,
4. domenowe kolory arkuszy,
5. czytelne helper tables.

Nie należy przenosić:

1. generowania workbooka przez `.mjs`,
2. twardych zakresów,
3. starego modelu danych,
4. proceduralnych chartów bez walidacji.
