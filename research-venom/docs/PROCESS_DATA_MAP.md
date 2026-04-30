# Process Data Map

Ten dokument opisuje techniczny przepływ danych w modelu badawczym: od parametrów wejściowych, przez dane źródłowe, po workbook i raporty walidacji.

## Przepływ danych

| Krok | Warstwa | Co powstaje |
|---|---|---|
| Parametry modelu | `artifacts/inputs/` | listy repozytoriów, listy projektów, specyfikacje workbooka i wykresów |
| Pobranie danych | `artifacts/sources/` oraz `artifacts/products_light/` | dane z GitHub API i SonarCloud API |
| Standaryzacja | `artifacts/processing/visualization/` | `sources_pack_v01.json`, `sources_pack_v01.csv` |
| Agregacja | `artifacts/processing/visualization/` | `summary_tables_v04.csv` |
| Prezentacja | `_external/not_tracked/visualization/` | workbook Excel i dokument Word |
| Walidacja | `artifacts/products_light/visualization/` | raporty JSON/MD dla Excela, Worda, audytu szablonu i pipeline |

## Źródła danych

| Źródło | Konfiguracja wejścia | Wynik techniczny |
|---|---|---|
| SonarCloud API | `artifacts/inputs/sonar_market/project_keys_selected_v01.txt` | dane dzienne per projekt oraz agregat kwartalny |
| GitHub API benchmark | `artifacts/inputs/github_market/repo_keys_selected_v01.txt` | dane dzienne per repo oraz agregat kwartalny |
| GitHub API dla Venom PR | `config/process_pipeline_v04.json` | PR flow i komentarze PR |
| Lokalna historia git Venom | lokalne repozytorium | metoda historyczna/kontrolna; nie jest źródłem aktywnego pipeline v4 |

Kontrakt trybów:
- tryb public/CI: `*_selected_v01.txt` (sample) + `config/process_pipeline_v04.json`,
- tryb testowy CI/offline: `*_selected_v01.txt` + `config/process_pipeline_v04_test.json`.

## Warstwy katalogów

| Katalog | Znaczenie |
|---|---|
| `artifacts/inputs/` | parametry sterujące badaniem |
| `artifacts/sources/` | dane pobrane lub zachowane jako materiał źródłowy |
| `artifacts/processing/` | dane złożone, ujednolicone i gotowe dla workbooka |
| `artifacts/products_light/` | lekkie wyniki, raporty i walidacje |
| `artifacts/meta/` | audyty, manifesty i metadane procesu |
| `_external/not_tracked/` | pliki ciężkie albo runtime, których nie śledzi git |

## Dane w workbooku

Workbook jest tworzony z `sources_pack` i specyfikacji layoutu.

| Typ arkusza | Rola | Przykłady |
|---|---|---|
| `raw` | dane pierwotne po standaryzacji | `Surowe_GitHub_Q1`, `Surowe_SonarQube_Q1`, `Surowe_PRFlow_Q1` |
| `analysis` | widoki robocze i przebiegi czasowe | `W32_LOC`, `W37_Trajektoria_Dlug`, `W42_FazaII` |
| `comparison` | agregacje i benchmarki | `WP1_PR_Wolumen`, `WP4_Backlog`, `WP6_Venom_Lead_Time` |

Arkusze `raw` pokazują dane pochodzące bezpośrednio z procesu standaryzacji. Arkusze `analysis` i `comparison` mogą zawierać agregacje, pivoty albo kolumny pomocnicze.

## Linie pochodzenia danych

| Widok w workbooku | Źródło logiczne | Charakter danych |
|---|---|---|
| GitHub benchmark | GitHub API dla listy repozytoriów, w tym `mpieniak01/Venom` | dane dzienne, potem agregacje |
| SonarCloud benchmark | SonarCloud API dla listy projektów | dane dzienne, potem agregacje jakości kodu |
| PR flow | GitHub API dla repozytorium Venom | dane dzienne i metryki kwartalne |
| PR comments | GitHub API dla zamkniętych PR | dane dzienne i podsumowania komentarzy |
| Template-matched visualization | połączone tabele summary | 21 chartów zgodnych z szablonem, bez `WP6_Market_Benchmark` |

## Kontrola jakości

Walidacja modelu obejmuje:

- obecność wymaganych arkuszy,
- obecność wykresów zgodnych ze specyfikacją,
- obecność kolumn źródłowych dla serii,
- wykrywanie serii pustych albo zbyt rzadkich,
- podstawową zgodność stylu z profilem workbooka,
- raportowanie przebiegu pipeline.

Raporty walidacyjne są lekkimi artefaktami w `artifacts/products_light/visualization/`.

## Zasada czytania artefaktów

Jeżeli trzeba sprawdzić wartość na wykresie, kolejność jest następująca:

1. znaleźć wykres w `chart_spec_v04.json`,
2. sprawdzić `source_sheet` i serie `x/y`,
3. znaleźć arkusz w `workbook_layout_v04.json`,
4. sprawdzić tabelę w workbooku,
5. porównać z raportem walidacji serii.

## Kontrola Antyregresyjna V4

Przed zmianą źródeł, tabel roboczych albo wykresów sprawdź [VISUALIZATION_V4_STABILITY_CONTRACT](VISUALIZATION_V4_STABILITY_CONTRACT.md).

Najczęstsze regresje, których ten projekt ma unikać:

1. `WP1`-`WP4` wracają do 6 projektów mimo 11 repozytoriów w `src_205D_timeseries`.
2. Arkusz ma `source_type` niezgodny z tabelą źródłową.
3. Daty w tabeli są tekstem albo mają literalne `YYYY` zamiast formatu `dd.mm.yyyy`.
4. Skrócony format daty z osi wykresu trafia do tabeli danych.
5. Fazy trafiają na oś główną i zmieniają skalę wykresu.
6. Wiersz 1 albo 2 zaczyna determinować szerokość kolumn danych.
