# research-venom

Projekt badawczy analizujący proces wytwarzania i utrzymania projektu Venom na tle wybranych repozytoriów referencyjnych oraz projektów porównawczych.

## Cel projektu

Celem projektu jest przygotowanie powtarzalnego modelu badawczego, który łączy dane z GitHub API oraz SonarCloud API, a następnie prezentuje je w workbooku Excel i artefaktach kontrolnych.

Model wspiera odpowiedź na pytania:

- jak wygląda aktywność i przepływ pracy w projekcie Venom,
- jak Venom wypada na tle wybranych repozytoriów GitHub,
- jak metryki jakości kodu i długu technicznego wyglądają względem wybranych projektów z SonarCloud,
- które dane są pierwotne, a które są wynikiem agregacji lub transformacji.

## Model badawczy

Model badawczy nie kopiuje danych z szablonu Excela. Szablon pełni rolę wzorca stylu i układu, natomiast dane pochodzą z pipeline:

1. pobranie danych ze źródeł,
2. standaryzacja do wspólnego pakietu danych,
3. agregacja i przygotowanie tabel pomocniczych,
4. budowa workbooka,
5. generowanie wykresów,
6. walidacja struktury, stylu i serii danych.

Ciężkie pliki runtime, takie jak `xlsx` i `docx`, są poza git w `_external/not_tracked/`. W `artifacts/` do publikowanego kontraktu należą tylko lekkie wejścia `artifacts/inputs/**`; warstwy `sources/processing/products_light/meta` pozostają danymi operacyjnymi poza zakresem publicznego release.
Aktualna baza `v04` rozwija kontrakt `v03` o legacy-inspired styling, `analysis_caption` i syntetyczne charty analityczne. Dalsze szczegóły kontraktu są opisane w [CHART_CONTROL_V4](docs/CHART_CONTROL_V4.md), a reguły antyregresyjne w [VISUALIZATION_V4_STABILITY_CONTRACT](docs/VISUALIZATION_V4_STABILITY_CONTRACT.md).

## Aktualne parametry modelu

| Parametr | Aktualna wartość |
|---|---|
| Okres badania | `2026-01-01` do `2026-03-31` |
| Baseline projektu | `mpieniak01/Venom` |
| Źródła GitHub | GitHub API |
| Źródła jakości kodu | SonarCloud API |
| Lista repozytoriów GitHub (public sample) | `artifacts/inputs/github_market/repo_keys_selected_v01.txt` |
| Lista projektów SonarCloud (public sample) | `artifacts/inputs/sonar_market/project_keys_selected_v01.txt` |
| Konfiguracja procesu v4 | `config/process_pipeline_v04.json` |
| Konfiguracja testowa v4 (sample) | `config/process_pipeline_v04_test.json` |
| Konfiguracja lokalna real (private) | `config/process_pipeline_v04_local_real.json` |

Parametry są częścią modelu. Zmiana okresu, listy repozytoriów albo listy projektów oznacza nowy przebieg badania, a nie ręczną korektę wykresów.
Listy `repo_keys_selected_v01.txt` i `project_keys_selected_v01.txt` są publicznymi listami sample.
Prywatne realne klucze trzymamy wyłącznie lokalnie poza gitem w `_external/not_tracked/inputs/**`, przez `config/process_pipeline_v04_local_real.json`.
Jawny kontrakt:
- GitHub CI uruchamia testy wyłącznie na sample (`config/process_pipeline_v04_test.json`).
- Lokalne środowisko uruchamia fetch i testy real-mode tylko przez prywatny config `config/process_pipeline_v04_local_real.json`.
- Kontrakt jest automatycznie egzekwowany przez `tools/verify_input_mode_contract.py`.
W `v04` workbook i wykresy są generowane z nowych tabel roboczych zgodnych z szablonem, ale dochodzi też warstwa narracyjna: `analysis_caption` dla chartów syntetycznych i wyraźniejsze wyróżnienie Venom w chartach porównawczych. Dla chartów opis źródła jest jawny: `source_domain` rozróżnia `GitHub API`, `SonarCloud API` i `PR flow`, a opisy tabel pokazują także liczby projektów wejściowych i renderowanych. Dla `W33_Dzienny_Przeplyw` źródłem metodycznym jest `Surowe_GitHub_Q1` / 205C z `mpieniak01/Venom` pobranym przez GitHub API. Lokalna historia git nie jest używana w aktywnym pipeline.
Stabilny kontrakt `v04` zakłada: GitHub benchmark = 11 repozytoriów, PR flow = 11 repozytoriów, SonarCloud = 11 projektów, PR comments = 1 repozytorium Venom. `WP1`-`WP4` pokazują pełne 11 repozytoriów PR flow; wcześniejsze ograniczenie do 6 projektów nie jest już aktywnym zachowaniem.
W chartach `combo` tło faz jest normalizowane do `100` na osi pomocniczej i renderowane jako `column`, więc nie zawyża zakresu osi głównej ani nie rozjeżdża wysokości bloków faz. Generator po utworzeniu wykresu ponownie wymusza `AxisGroup=secondary` dla wszystkich serii `phase_*`, bo Excel COM potrafi automatycznie przenieść pierwszą serię kolumnową na oś główną. To jest ważne zwłaszcza dla `W37_Trajektoria_Dlug`, `W35_Trajektoria_Q1`, `W42_FazaII`, `W43_FazaII`, `W33_Dzienny_Przeplyw`, `WP5_Venom_PR_Daily` i `WP6_Venom_Lead_Time`.
W WP5/WP6 fazy są rysowane jako lekkie, przezroczyste tło, żeby nie przykrywać danych PR i lead time.
Typ wykresu zależy od semantyki metryki: stany ciągłe mogą być linią, ale metryki zdarzeniowe i sparse są kolumnami. Dlatego `WP6_Venom_Lead_Time` nie jest już linią trendu, tylko kolumnowym widokiem zdarzeń PR, a charty jednofazowe pokazują tylko aktywną fazę.
Zakres osi dat jest również sterowany konfiguracją. Jeżeli chart ma dane dopiero od fazy II, np. `W37_Trajektoria_Dlug`, oś X zaczyna się od `2026-02-06`, zamiast pokazywać pusty styczeń.
Opis arkuszy i tabel jest teraz source-first: najpierw wskazuje `src_*` albo `wrk_*`, potem tabelę pośrednią, dopiero potem skrót biznesowy.
Oś dat jest sterowana globalnym profilem kategorii: etykiety pokazują `mm-dd`, ticki idą tygodniowo, bez powtarzania roku `2026` na każdym wykresie.
W tabelach workbooka kolumny dat pozostają datami Excela w formacie `dd.mm.yyyy`; skrót `mm-dd` dotyczy wyłącznie osi wykresu. Wiersze 1 i 2 arkusza są zwykłymi, niescalonymi i niezawijanymi komórkami opisowymi i nie mogą determinować szerokości kolumn danych.
Dla chartów porównawczych `WP1`-`WP4` działa kontrakt `Venom anchor`: `mpieniak01/Venom` jest zawsze obecny, a wykres pokazuje pełne 11 repozytoriów z danych PR flow. Lista kluczy projektów jest pokazywana w pełni, bez grupowania do `inne`, a opisy rozróżniają liczbę repozytoriów wejściowych i liczbę projektów pokazanych na wykresie.

## Wyniki i artefakty

Główne produkty wynikowe:

- workbook Excel: `_external/not_tracked/visualization/workbook_v04.xlsx`,
- raport walidacji workbooka: `artifacts/products_light/visualization/excel_verify_v04.md`,
- audyt szablonu wykresów: `artifacts/products_light/visualization/template_chart_audit_v04.md`,
- dokument Word z osadzonymi wykresami: `_external/not_tracked/visualization/embed_canvas_bookmarked_v04.docx`,
- raport osadzeń Word: `artifacts/products_light/visualization/word_embed_verify_v04.md`,
- raport przebiegu pipeline: `artifacts/products_light/visualization/pipeline_run_v04.md`.

## Jak czytać workbook

Workbook ma dwie główne warstwy:

- arkusze surowe, np. `Surowe_GitHub_Q1`, `Surowe_SonarQube_Q1`, `Surowe_PRFlow_Q1`, pokazują dane pierwotne po standaryzacji,
- arkusze analityczne i porównawcze, np. `W31_Commity`, `W33_Dzienny_Przeplyw`, `WP1_PR_Wolumen`, `WP4_Backlog`, `WP6_Venom_Lead_Time`, pokazują dane zagregowane, pivotowane albo przekształcone na potrzeby interpretacji.

Tabela w arkuszu jest częścią modelu, nie dodatkiem do wykresu. Wykres powinien dać szybki obraz, a tabela pozwala sprawdzić, z jakich wartości powstała seria.

## Dokumentacja

Dla czytelnika biznesowego i naukowego:

- [RESEARCH_MODEL](docs/RESEARCH_MODEL.md) — pytanie badawcze, parametry, źródła danych, interpretacja workbooka i ograniczenia.
- [PROCESS_DATA_MAP](docs/PROCESS_DATA_MAP.md) — techniczna mapa pochodzenia danych od źródeł do workbooka.
- [VISUALIZATION_V4_STABILITY_CONTRACT](docs/VISUALIZATION_V4_STABILITY_CONTRACT.md) — aktualny kontrakt stabilności v4: źródła, formaty dat, style, fazy i zasady antyregresyjne.
- [RELEASE_CHECKLIST](docs/RELEASE_CHECKLIST.md) — checklista publikacji GitHub: jakość, bezpieczeństwo, odtwarzalność i known limits.
- [PROJECT_SOURCE_POPULATION_V4](docs/PROJECT_SOURCE_POPULATION_V4.md) — liczba projektów w źródłach GitHub, PR flow i SonarCloud oraz reguły prezentacji na wykresach.
- [CHART_CONTROL_V3](docs/CHART_CONTROL_V3.md) — kontrakt dla v3: role serii, tryby wykresów i osi pomocnicze.
- [LEGACY_TEMPLATE_MJS_REVIEW](docs/LEGACY_TEMPLATE_MJS_REVIEW.md) — analiza historycznego generatora `04_przygotuj_arkusze_wykresow.mjs` i decyzja, co można traktować jako inspirację, a czego nie przenosić do v3.

Dla czytelnika technicznego:

- [SCRIPTS_REFERENCE](docs/SCRIPTS_REFERENCE.md) — katalog narzędzi, wejść i wyjść każdego kroku.
- [PIPELINE_RUNTIME_BANDS](docs/PIPELINE_RUNTIME_BANDS.md) — empiryczne zakresy czasów kroków i kontekst sprzętowy.
- [EXECUTION_ENV](docs/EXECUTION_ENV.md) — środowisko uruchomieniowe, Python, PowerShell i Office COM.
- [EXCEL_ADVANCED_PATTERNS](docs/EXCEL_ADVANCED_PATTERNS.md) — dodatkowe wzorce narracyjne dla wykresów Excela.


## Makefile i szybkie komendy

Podstawowym interfejsem pracy dla ludzi i agentow AI jest `Makefile`. Zaczynaj od:

```bash
make help
```

Najwazniejsze grupy komend:

- `make test-contracts` - szybkie testy kontraktow logiki, bez API, bez Office, zgodne z CI.
- `make test-contracts-ci` - pełny kontrakt CI: sample inputs + testy + static + parse.
- `make test-contracts-local-real` - lokalny kontrakt real-mode: `v04` musi wskazywać na realne listy kluczy.
- `make test-data-local` - lokalne testy jakosci aktualnych artefaktow; nie sa uruchamiane w publicznym CI.
- `CONFIRM_API=1 make fetch-*` - jawne pobieranie danych z API. Te kroki sa kosztowne i nie sa domyslne.
- `make process` - lokalne S01+S02 na juz pobranych artefaktach, bez sieci i bez Office.
- `make product-excel-only` - generowanie workbooka Excel przez Windows Office COM, bez pobierania danych z API.

`make all` nie jest kontraktem procesu i nie powinien pobierac danych z API. Pobieranie danych zawsze wymaga jawnej decyzji przez `CONFIRM_API=1`.

## Uruchamianie

Aktywacja Python:

```bash
source .venv/bin/activate
```

Pipeline z krokami Office COM uruchamiamy przez Windows PowerShell:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath config/process_pipeline_v04.json
```

`pwsh` w Linux/WSL nadaje się do parse-checków i kroków bez Office COM, ale nie zastępuje Windows `powershell.exe` dla automatyzacji Word/Excel.
