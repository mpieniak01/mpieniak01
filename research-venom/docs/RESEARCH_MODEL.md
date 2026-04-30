# Research Model

Ten dokument opisuje model badawczy stojący za workbookiem i raportami projektu `research-venom`.

## Pytanie badawcze

Badanie sprawdza, jak proces pracy nad projektem Venom wygląda na tle wybranych repozytoriów i projektów rynkowych.

Model łączy dwie perspektywy:

- aktywność developerska i przepływ PR w GitHub,
- metryki jakości kodu oraz długu technicznego z SonarCloud.

Celem nie jest pojedynczy wykres, tylko powtarzalny sposób zebrania, przetworzenia i sprawdzenia danych.

## Parametry modelu

Aktualny przebieg modelu jest sparametryzowany następująco:

| Parametr | Wartość |
|---|---|
| Zakres dat | `2026-01-01` do `2026-03-31` |
| Projekt bazowy | `mpieniak01/Venom` |
| Repozytoria benchmarku GitHub | `artifacts/inputs/github_market/repo_keys_selected_v01.txt` |
| Projekty benchmarku SonarCloud | `artifacts/inputs/sonar_market/project_keys_selected_v01.txt` |
| Konfiguracja pipeline | `config/process_pipeline_v04.json` |
| Konfiguracja pipeline test (sample) | `config/process_pipeline_v04_test.json` |
| Definicja workbooka | `artifacts/inputs/visualization/workbook_layout_v04.json` |
| Definicja wykresów | `artifacts/inputs/visualization/chart_spec_v04.json` |
| Profil stylu | `artifacts/inputs/visualization/chart_style_profile_v04.json` |

Zmiana któregokolwiek z tych parametrów zmienia przebieg badania. Workbook powinien być wtedy wygenerowany ponownie z pipeline, a nie korygowany ręcznie.
Tryb testowy jest jawnie odseparowany: `config/process_pipeline_v04_test.json` i publiczny kontrakt `config/process_pipeline_v04.json` używają tych samych publicznych list sample (`*_selected_v01.txt`). Lokalny przebieg realny wymaga prywatnego `config/process_pipeline_v04_local_real.json` i plików poza gitem w `_external/not_tracked/inputs/**`.

## Źródła danych

Model korzysta z czterech klas danych:

| Źródło | Rola w badaniu | Przykładowe metryki |
|---|---|---|
| GitHub API dla repozytoriów benchmarku, w tym `mpieniak01/Venom` | aktywność rynkowa | commits, authors, additions, deletions, churn |
| SonarCloud API dla projektów benchmarku | jakość kodu i dług techniczny | issues, technical debt, lines of code, coverage, unit tests |
| GitHub API dla Venom | przepływ PR i współpraca | opened, merged, active PR, lead time, review latency |

Szablon Excela nie jest źródłem danych. Służy tylko jako wzorzec układu, kolorystyki, wielkości wykresów i sposobu prezentacji tabel obok wykresów.
W `v04` szablon jest dodatkowo wzorcem merytorycznym dla układu wykresów: workbook ma 17 arkuszy i 21 chartów zgodnych z `Wykresy_Venom_FORMULY_v6.xlsx`.

Wariant lokalnego `git log --numstat` był użyty jako techniczna diagnoza brakujących danych `W33`, ale nie jest częścią aktywnej metody v4. Aktywny pipeline wymaga obecności `mpieniak01/Venom` w 205C z GitHub API.

## Warstwy danych

Model rozdziela dane na warstwy:

| Warstwa | Znaczenie |
|---|---|
| `artifacts/inputs/` | parametry, listy repozytoriów, listy projektów, layouty i mapy |
| `artifacts/sources/` | dane pobrane z API |
| `artifacts/processing/` | dane ujednolicone i przygotowane do workbooka |
| `artifacts/products_light/` | raporty, walidacje i lekkie wyniki |
| `_external/not_tracked/` | ciężkie pliki runtime: workbooki, dokumenty Word, eksporty |

Najważniejszym punktem przejścia jest `sources_pack`: łączy dane z wielu źródeł w jeden kontrakt wejściowy dla workbooka.

## Jak czytać workbook

Workbook ma arkusze źródłowe oraz arkusze wynikowe.

Arkusze źródłowe:

| Arkusz | Znaczenie |
|---|---|
| `Surowe_GitHub_Q1` | ustandaryzowane dane dzienne z benchmarku GitHub |
| `Surowe_SonarQube_Q1` | ustandaryzowane dane dzienne z SonarCloud |
| `Surowe_PRFlow_Q1` | ustandaryzowane dane dzienne dla przepływu PR |

Arkusze analityczne i porównawcze:

| Typ | Znaczenie |
|---|---|
| `analysis` | pokazuje przebiegi czasowe i szczegółowe widoki dla wybranych źródeł |
| `comparison` | pokazuje agregacje, porównania między repozytoriami lub metryki podsumowujące |

W arkuszach wynikowych tabela i wykres są równorzędne. Tabela pokazuje wartości użyte do serii, a wykres pokazuje ich interpretację wizualną.
W `WP6_Venom_Lead_Time` zachowana jest tylko para sygnałów lead time z tłem faz, bo taki jest kontrakt szablonu.

## Agregacje i transformacje

Model wykonuje agregacje, bo część pytań badawczych nie dotyczy pojedynczego dnia, tylko zachowania w całym kwartale.

Przykłady:

- dzienne metryki PR są agregowane do wolumenu, backlogu i lead time,
- dane SonarCloud są uśredniane lub pivotowane do porównania projektów,
- dane w układzie long mogą zostać przekształcone do układu wide, jeżeli taki format jest właściwy dla wykresu.

Kolumny pomocnicze, takie jak `days_in_window`, opisują kontekst obliczeń. Nie każda kolumna tabeli jest serią wykresu.

## Walidacja

Model ma walidację techniczną i merytoryczną serii:

- sprawdza, czy arkusze i wykresy istnieją,
- sprawdza, czy seria wykresu ma kolumnę źródłową,
- wykrywa serie puste,
- oznacza serie zbyt rzadkie albo częściowo brakujące,
- sprawdza zgodność podstawowych elementów stylu workbooka.

Raport walidacji znajduje się w `artifacts/products_light/visualization/excel_verify_v04.md`.

## Ograniczenia interpretacyjne

Model jest porównawczy, a nie kauzalny. Pokazuje różnice w metrykach, ale sam nie dowodzi przyczyn.

Najważniejsze ograniczenia:

- dobór repozytoriów i projektów wpływa na wynik benchmarku,
- API GitHub i SonarCloud mogą mieć własne ograniczenia kompletności danych,
- metryki PR opisują proces pracy, ale nie mierzą bezpośrednio wartości biznesowej,
- lead time i review latency są interpretowane jako proxy procesu, nie jako pełny obraz organizacji pracy.

Wnioski z workbooka powinny być czytane razem z tabelami źródłowymi, opisem parametrów i raportem walidacji.

Warstwa `v04` dla bardziej zaawansowanego sterowania wykresami jest opisana osobno w [CHART_CONTROL_V4](CHART_CONTROL_V4.md).
Stabilny kontrakt antyregresyjny dla workbooka `v04` jest opisany w [VISUALIZATION_V4_STABILITY_CONTRACT](VISUALIZATION_V4_STABILITY_CONTRACT.md). Ten dokument jest nadrzędny dla decyzji typu: liczba projektów na wykresach, format dat, mapowanie `source_type`, style arkuszy, tło faz i widoczność Venom.
