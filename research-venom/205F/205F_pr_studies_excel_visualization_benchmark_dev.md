# 205F - Wizualizacja wyników badań 205 w Excel (editable charts)

Data: `2026-04-27`
Status: `planned`
Priorytet: `P1`
Powiązanie:
1. `205B/205B_pr_studies_market_benchmark_sonar_api_problem_definition_dev.md`
2. `205C/205C_pr_studies_market_benchmark_github_api_repository_search_dev.md`
3. `205D/205D_pr_studies_pr_flow_efficiency_git_github_dev.md`
4. `205E/205E_pr_studies_comments_evidence_dev.md`

## 0. Problem

Dane serii 205 są poprawnie zebrane, ale do rozdziału analitycznego pracy potrzebna jest spójna warstwa wizualna.
Wymaganie metodyczne: wykresy mają być edytowalne w Excel (nie tylko statyczne PNG), aby umożliwić ręczne dopracowanie wyglądu i osi bez przebudowy pipeline.

## 1. Cel PR 205F

Przygotować standaryzowany zestaw wykresów dla danych 205B/205C/205D/205E w formie natywnego pliku `.xlsx` oraz pomocniczych eksportów.

## 2. Zakres PR

### 2.1 In-scope

1. Ujednolicenie źródeł wejściowych do formatu tabelarycznego pod Excel.
2. Budowa skoroszytu `205F_visualization_q1_2026.xlsx` z kartami tematycznymi.
3. Dodanie zestawu wykresów edytowalnych (Excel chart objects).
4. Ustalenie standardu stylu (tytuły, osie, legenda, kolory, nazwy serii).
5. Zapis konfiguracji i metadanych wykresów (manifest JSON + krótki raport MD).

### 2.2 Out-of-scope

1. Zaawansowana grafika DTP i finalny skład publikacyjny.
2. Dashboard BI poza Excelem.
3. Interaktywne wykresy webowe.

## 3. Źródła danych (wejście)

1. `205B/timeseries/205B_timeseries_q1_2026.csv`
2. `205C/timeseries/205C_github_benchmark_q1_2026.csv`
3. `205D/timeseries/205D_pr_flow_q1_2026.csv`
4. `205E/timeseries/csv/205E_pr_comments_q1_2026_daily.csv`
5. (opcjonalnie) dane per-repo z `csv/` w seriach 205B/205C/205D/205E.

## 4. Docelowe wykresy

1. `LOC trend Venom (Q1 2026)` - linia dzienna (`date` vs `lines_of_code`).
2. `Issues vs Technical Debt (Venom)` - dual-axis line/column lub dwa wykresy liniowe.
3. `PR flow daily (Venom)` - otwarte, zmergowane, aktywne PR (linie).
4. `Median lead time PR - porównanie repo` - poziomy wykres słupkowy.
5. `Backlog pressure - średnia aktywnych PR` - poziomy wykres słupkowy.
6. `Komentarze PR (205E)` - dzienny trend i podsumowanie średnia/mediana.
7. `Porównanie benchmarkowe 205B/205C` - wykresy kolumnowe dla metryk końcowych.

## 4A. Typologia wykresów

1. Typ A - `prezentacja stanu`:
   - wykresy proste, pokazujące stan/trend bez dodatkowej warstwy narracyjnej.
2. Typ B - `wykresy opisowe`:
   - wykresy z warstwą narracyjną i dodatkowymi elementami analitycznymi.

## 5. Metodyka wizualizacji

1. Jeden skoroszyt, wiele kart: `summary` (najpierw), potem `charts`, dalej karty źródłowe i przetworzone.
2. Każde źródło jako tabela Excel (ułatwia filtrowanie i edycję serii).
3. Wykresy osadzane natywnie jako obiekty Excela (editable).
4. Standard nazewnictwa wykresów: `chart_<seria>_<temat>`.
5. Standard osi czasu: zakres `2026-01-01` -> `2026-03-31`.
6. Braki danych (`null`) pozostają puste, bez sztucznego imputowania.
7. Każdy wykres dostaje stały `chart_id` i jawnie zdefiniowane serie danych.

## 5A. Standard arkusza Excel (kolejność zakładek)

1. `summary` - dane sumaryczne do rozdziału analitycznego.
2. `charts` - główne wykresy do osadzania w Word.
3. `src_*` - źródła czyste (bez przetwarzania).
4. `wrk_*` - dane pośrednie/przetworzone pod wykresy.
5. `meta` - słownik wykresów, wersje, zakresy źródeł.

## 5B. Standard identyfikacji wykresów i serii

1. `chart_id` format: `C_<SERIA>_<TEMAT>_<NN>`, np. `C_205D_LEAD_TIME_01`.
2. Nazwa obiektu wykresu w Excel = `chart_id` (brak lokalnych aliasów).
3. Dla każdego wykresu definiujemy:
   - `x_series`,
   - `y_series[]`,
   - filtr projektu/zakresu dat,
   - źródło (`src_*` lub `wrk_*`).
4. Zmiana definicji serii = nowa wersja specyfikacji (`_vNN`), bez podmiany historycznej.

## 5C. Kontrola osadzania Excel -> Word

1. Każdy wykres ma mapowanie do bookmarka Word:
   - `word_bookmark`: `BM_<chart_id>`.
2. Osadzanie odbywa się po `chart_id`, nie po kolejności wykresów na stronie.
3. Jedynym źródłem prawdy mapowania jest plik `205F_word_embed_map_vNN`.
4. Brak mapowania = wykres nie może być traktowany jako gotowy do publikacji.

## 5D. Techniki Excel dla wykresów opisowych (Typ B)

1. `background_series` - serie pomocnicze do kolorowania tła (np. fazy procesu).
2. `label_series` - serie etykietowe do oznaczania punktów krytycznych.
3. `reference_lines` - linie pionowe/poziome dla progów i punktów granicznych.
4. `annotation_shapes` - teksty/kształty/strzałki osadzane jako obiekty w Excel.
5. Każdy element z pkt 1-4 musi być zapisany w specyfikacji wykresu (kontrola odtwarzalności).

## 6. Plan narzędziowy

1. Skrypty pomocnicze pozostają w:
   - `tools/`
2. Dla 205F planowany skrypt roboczy:
   - `tools/excel_205f_visualization.py` (lub `.ps1` dla COM Excel)
3. Tryb uruchomienia: z root repo Venom.

## 7. Kryteria akceptacji

1. Powstaje `xlsx` z min. 7 wykresami z sekcji 4.
2. Wszystkie wykresy są edytowalne bezpośrednio w Excel.
3. Każdy wykres ma tytuł, opisy osi i legendę.
4. Ścieżki wejściowe i wyjściowe są zapisane w manifeście 205F.
5. Raport MD opisuje co przedstawia każdy wykres i z jakich danych korzysta.
6. Każdy wykres ma `chart_id` i wpis w mapie `Excel->Word`.
7. Każdy wykres ma jawnie zdefiniowaną serię danych (`x_series`, `y_series[]`).
8. Dla wykresów Typu B jawnie opisano elementy narracyjne (`background_series`, `label_series`, `reference_lines`, `annotation_shapes`).

## 8. Produkty (co przedstawiają)

1. `produkty/excel/workspace/205F_visualization_workspace.xlsx`
   - główny skoroszyt roboczy (produkt pośredni) z zakładkami źródłowymi i wykresami editable.
2. `produkty/word/final/Projekt_Koncowy_Pieniak_FINAL8_bibliografia_pl_miesiace_gotowe.docx`
   - główny produkt końcowy pracy (Word) z osadzonymi tabelami i wykresami.
3. `produkty/excel/exports/*.png`
   - opcjonalny eksport poglądowy wykresów do prezentacji.
4. `205F/analysis/205F_analiza_wizualizacji_q1_2026.json`
   - manifest źródeł, definicji wykresów i zakresów danych.
5. `205F/analysis/205F_analiza_wizualizacji_q1_2026.md`
   - opis metodyki i interpretacja zestawu wykresów.
6. `205F/inputs/205F_chart_spec_v01.json`
   - specyfikacja wykresów (typ, osie, serie, filtry, karta docelowa, `chart_id`).
7. `205F/inputs/205F_word_embed_map_v01.csv`
   - mapa osadzania `Excel chart_id -> Word bookmark`.
8. `205F/inputs/205F_excel_sheet_layout_v01.csv`
   - definicja kolejności zakładek i roli każdej karty.
9. `205F/inputs/205F_excel_advanced_patterns_v01.md`
   - katalog technik dla wykresów opisowych (Typ B) i ich użycia.
10. `205F/inputs/205F_bibliografia_zrodla_v01.md`
   - kontrolowana bibliografia źródeł zewnętrznych i wewnętrznych.
11. `205F/inputs/205F_bibliografia_zrodla_v01.csv`
   - tabelaryczny rejestr bibliografii do dalszego przetwarzania.
