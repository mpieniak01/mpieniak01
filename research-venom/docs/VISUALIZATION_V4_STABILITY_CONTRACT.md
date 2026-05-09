# VISUALIZATION V4 STABILITY CONTRACT

Ten dokument opisuje stabilny kontrakt workbooka `v04`. Ma zapobiegać regresjom typu: inna liczba projektów na wykresie niż w źródle, pomieszane domeny danych, cofnięcie formatów dat, rozjazd stylu arkuszy albo ponowne ukrycie Venom w benchmarkach.

## Źródła Prawdy

Aktywne pliki kontraktu `v04`:

| Obszar | Plik |
|---|---|
| Pipeline | `config/process_pipeline_v04.json` |
| Układ arkuszy | `artifacts/inputs/visualization/workbook_layout_v04.json` |
| Definicje wykresów | `artifacts/inputs/visualization/chart_spec_v04.json` |
| Styl | `artifacts/inputs/visualization/chart_style_profile_v04.json` |
| Sterowanie seriami i osiami | `artifacts/inputs/visualization/chart_control_profile_v04.json` |
| Mapowanie Word | `artifacts/inputs/visualization/word_embed_map_v04.csv` |
| Szablon referencyjny | `artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx` |

`v03` i starsze pliki są archiwalnym punktem odniesienia. Nie są aktywnym kontraktem generowania workbooka.

## Populacje Źródeł

W `v04` liczba projektów nie może być zgadywana z wyglądu wykresu. Musi wynikać ze źródła i opisu tabeli.

| Źródło | Tabela | Populacja | Zastosowanie |
|---|---|---:|---|
| GitHub API benchmark | `src_205C_timeseries` | 11 repozytoriów | commit, additions, deletions, code flow |
| GitHub PR flow | `src_205D_timeseries` | 11 repozytoriów | PR volume, lead time, merge rate, backlog |
| SonarCloud API | `src_205B_timeseries` | 11 projektów Sonar | issues, technical debt, coverage, tests |
| GitHub PR comments | `src_205E_daily` | 1 repozytorium | komentarze PR tylko dla `mpieniak01/Venom` |

Regresja niedozwolona:

1. `WP1`-`WP4` nie mogą wrócić do `6` projektów jako domyślnego widoku.
2. `comparison_peer_group_size` w aktywnym `v04` ma pozostać `11`, jeśli nie ma świadomej zmiany metodologii.
3. GitHub i SonarCloud nie muszą mieć identycznych kluczy projektów, ale muszą mieć jawnie opisane domeny.
4. Lokalna historia git nie jest aktywnym źródłem danych dla workbooka `v04`.

## Reguły Prezentacji Projektów

| Arkusze | Źródło | Pokazywane projekty |
|---|---|---:|
| `W31`, `W32` | GitHub API benchmark | 11 |
| `W36` | SonarCloud API | 11 |
| `W37`, `W35`, `W42`, `W43` | SonarCloud API | 1, tylko Venom |
| `W33` | GitHub API benchmark | 1, tylko Venom |
| `WP1`-`WP4` | GitHub PR flow | 11 |
| `WP5`, `WP6` | GitHub PR flow | 1, tylko Venom |

Dla chartów porównawczych obowiązuje `Venom anchor`: `mpieniak01/Venom` musi być obecny, a pełna lista kluczy projektów ma być widoczna w danych i metadanych. Nie wolno zastępować pełnych nazw projektów skrótem `inne`.

## Domeny Danych I `source_type`

`source_type` steruje stylem domenowym i musi odpowiadać realnemu źródłu danych.

| `source_type` | Dozwolone źródło |
|---|---|
| `github` | `src_205C_timeseries` i tabele pochodne GitHub benchmark |
| `sonarqube` | `src_205B_timeseries` i tabele pochodne SonarCloud |
| `git_prflow` | `src_205D_timeseries` i tabele pochodne PR flow |

Regresja niedozwolona:

1. Arkusz SonarCloud nie może mieć `source_type: github` albo `git_prflow`.
2. Arkusz PR flow nie może mieć stylu SonarCloud tylko dlatego, że pokazuje lead time albo procenty.
3. `W32_LOC` i `W33_Dzienny_Przeplyw` są GitHub API benchmark, nie SonarCloud.
4. `WP5_Venom_PR_Daily` i `WP6_Venom_Lead_Time` są PR flow, nie GitHub comments.

## Daty

Obowiązują dwa różne formaty, bo tabela i wykres mają różne cele.

| Miejsce | Format |
|---|---|
| Dane w tabeli workbooka | data Excela z formatem `dd.mm.yyyy` |
| Etykieta osi dat na wykresie | `mm-dd` |
| Częstotliwość etykiet osi | co 7 dni |

Regresja niedozwolona:

1. Nie wolno generować tekstu `YYYY-...` jako daty w komórce.
2. Komórki dat mają być datami Excela, nie ręcznie składanym stringiem.
3. Rok `2026` nie ma być powtarzany na każdej etykiecie osi wykresu.
4. Skrócony format `mm-dd` dotyczy wykresu, nie tabeli danych.

## Fazy Projektu

Fazy są globalnym tłem projektu, nie danymi biznesowymi.

| Faza | Zakres |
|---|---|
| Faza I - Generowanie | `2026-01-01` do `2026-02-05` |
| Faza II - Oczyszczanie | `2026-02-06` do `2026-03-06` |
| Faza III - Stabilizacja | `2026-03-07` do `2026-03-31` |

Kontrakt techniczny:

1. Serie `phase_*` są renderowane jako tło na osi pomocniczej.
2. Wysokość tła faz to `100` na osi pomocniczej `0..100`.
3. `phase_*` nie mogą wpływać na skalę osi głównej.
4. Jeśli wykres ma dane tylko od fazy II, oś X może zaczynać się od fazy II; nie trzeba pokazywać pustej fazy I.
5. Serie faz są pomocnicze i powinny być pierwsze w `series_plan`.

## Typy Wykresów

Dobór typu wykresu wynika z semantyki danych.

| Dane | Preferowany typ |
|---|---|
| Porównanie projektów | `bar_horizontal` |
| Wolumen PR z kategoriami | `bar_stacked` albo wariant porównawczy z highlight Venom |
| Dane ciągłe / trend | `line` |
| Zdarzenia dzienne i sparse metrics | `column` |
| Tło faz | `column` na osi pomocniczej |
| Wykres syntetyczny | `synthetic_combo` / `combo` z jawnie opisanym celem |
| Wykres zbiorczy arkusza | `sheet_synthesis` |

Regresja niedozwolona:

1. `WP6_Venom_Lead_Time` nie powinien wracać do linii trendu, jeśli dane są zdarzeniowe i nieciągłe.
2. Sparse/event metrics nie powinny udawać ciągłego trendu.
3. Chart jednofazowy nie musi pokazywać pustych faz bez danych.

## Styl Workbooka

Styl `v04` jest oparty o szablon Excel i elementy legacy, ale tylko przez aktualny profil stylu.

Obowiązujące zasady arkusza:

1. Tytuł arkusza jest zwykłą komórką, bez scalania i bez zawijania.
2. Podtytuł/opis jest zwykłą komórką, bez scalania i bez zawijania.
3. Wiersze 1 i 2 nie determinują szerokości kolumny A.
4. Szerokości kolumn wynikają z nagłówków tabeli danych, przede wszystkim z wiersza nagłówkowego serii, z lekkim zapasem.
5. Arkusze prezentacyjne mają wyłączoną siatkę.
6. Tabele mają nagłówki, filtry, obramowania i banded rows.

Obowiązujące kolory i fonty z profilu `v04`:

| Element | Wartość |
|---|---|
| Tytuł wykresu | Calibri 14, bold, `#0F172A` |
| Tytuł arkusza A1 | Calibri 14, bold, tło `#FFFFFF`, font z koloru tła nagłówka tabeli/domeny |
| Etykiety osi | Calibri 10, `#374151` |
| Legenda | Calibri 11, bold, `#1E3A8A`, domyślnie z profilu `top`, w v04 chart spec wymusza zwykle `bottom` |
| Nagłówek tabeli | fill `#1E3A8A` albo domenowy `source_type_palette.*.header_fill_rgb`, font biały |
| Chart area | `#FFFFFF` |
| Plot area | `#FFFFFF` |
| Ramka chart area | `#D1D5DB`, 0.5 pt |

Paleta domenowa:

| Domena | Header | Accent |
|---|---|---|
| GitHub | `#7C3AED` | `#EDE9FE` |
| SonarCloud | `#0F766E` | `#CCFBF1` |
| PR flow | `#1E3A8A` | `#DBEAFE` |
| Summary | `#1E3A8A` | `#E2E8F0` |

Regresja niedozwolona:

1. Nie wracać do scalonych nagłówków arkusza.
2. Nie zawijać wiersza 1 i 2 jako sposobu na kontrolę szerokości kolumn.
3. Nie mieszać kolorów faz z kolorami domen danych.
4. Nie usuwać ramki i czytelnego stylu słupków bez świadomej zmiany profilu stylu.

## Walidacja Przed Uznaniem Zmiany Za Gotową

Minimalny zestaw kontroli po zmianie workbooka:

```bash
make test
make product-excel-v4
```

Oczekiwane warunki:

1. `make test` przechodzi.
2. Pipeline `v04` kończy się statusem `ok`.
3. `S04` tworzy 26 wykresów.
4. `excel_verify_v04` ma `charts_failed: 0`.
5. Ostrzeżenia `series_too_sparse` są dopuszczalne dla sparse metrics, jeśli nie ma brakujących kolumn źródłowych.
6. `WP1`-`WP4` mają `rendered_project_count: 11`.
7. `source_type` arkuszy przechodzi test kontraktowy.

## Dokumenty Powiązane

1. `docs/PROJECT_SOURCE_POPULATION_V4.md` - liczby projektów i reguły prezentacji.
2. `docs/CHART_CONTROL_V4.md` - sterowanie wykresami, fazami i walidacją.
3. `docs/RESEARCH_MODEL.md` - model badawczy i interpretacja wyników.
4. `docs/PROCESS_DATA_MAP.md` - ścieżka danych od źródła do workbooka.
5. `docs/EXCEL_ADVANCED_PATTERNS.md` - wzorce zaawansowanych wykresów i narracji.
6. `docs_pr/_todo/211A_pr_visualization_legacy_style_and_synthetic_charts_v01.md` - zakres i decyzje PR 211A.
7. `docs_pr/_todo/214A_pr_visualization_sheet_level_synthetic_charts_v01.md` - zakres i decyzje dla wykresów zbiorczych arkusza.
