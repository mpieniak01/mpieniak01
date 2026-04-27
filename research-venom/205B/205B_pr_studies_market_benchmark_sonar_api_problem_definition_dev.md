# 205B - Benchmark rynkowy przez SonarQ API: opis problemu i zakres PR

Data: `2026-04-22`  
Status: `planned`  
Priorytet: `P1`  
Powiązanie:
1. `205/analysis/205_analiza_pr.md`
2. `205/205_pr_studies_ai_software_process_automation_git_code_analysis_dev.md`

## 0. Kontekst

W projekcie `Venom` mamy już policzone metryki zmian (Git + PR) dla własnego repozytorium. Brakuje jednak punktu odniesienia do rynku, przez co trudno obronić wnioski typu: „czy nasze tempo i jakość zmian są wysokie, przeciętne czy niskie względem podobnych projektów”.

## 1. Opis problemu (205B)

Obecny materiał do pracy inżynierskiej opisuje tylko jeden przypadek (`Venom`).
To ogranicza wartość analityczną, bo:
1. nie mamy porównania do publicznych projektów o podobnym profilu,
2. nie mamy benchmarku metryk jakościowych (np. reliability/security/maintainability),
3. nie da się pokazać pozycji `Venom` na tle rynku w sposób powtarzalny i oparty o dane.

Problem do rozwiązania:
`Jak zbudować powtarzalny benchmark rynkowy na bazie SonarQ API dla publicznych projektów i porównać go z wynikami Venom?`

## 2. Cel PR 205B

Przygotować i uruchomić proces pozyskania danych z SonarQ API dla wybranej grupy publicznych projektów, a następnie zbudować porównanie `Venom vs rynek` w formie raportu i datasetu.

## 3. Zakres PR

### 3.1 In-scope

1. Zdefiniowanie kryteriów doboru projektów referencyjnych (publiczne, aktywne, technologicznie porównywalne).
2. Pobranie listy kandydatów oraz metadanych projektów z SonarQ API.
3. Pobranie metryk jakościowych i utrzymaniowych dla każdego projektu referencyjnego.
4. Pobranie obowiązkowego pakietu metryk porównawczych z innych projektów:
   - `Issues`,
   - `Technical Debt (days)`,
   - `Lines of Code`,
   - `Line Coverage (%)`,
   - `Unit Tests`.
5. Ujednolicenie metryk do wspólnego formatu porównawczego (`Venom` + benchmark).
6. Wyliczenie podstawowych statystyk benchmarku (mediana, kwartyle, pozycja percentylowa `Venom`).
7. Opracowanie raportu: różnice, odchylenia, mocne/słabe strony `Venom` względem rynku.

### 3.2 Out-of-scope

1. Ręczna ocena jakości kodu pojedynczych repozytoriów.
2. Analiza kosztów chmury, CI runtime i kosztów infrastruktury konkurencyjnych projektów.
3. Długoterminowe monitorowanie trendów (to może być osobny PR).

## 4. Minimalny zestaw metryk porównawczych

### 4.1 Zestaw obowiązkowy (rdzeń benchmarku międzyprojektowego)

1. `Issues` -> `violations` (fallback: `open_issues`)
2. `Technical Debt (days)` -> `sqale_index` (konwersja minut na dni)
3. `Lines of Code` -> `ncloc`
4. `Line Coverage (%)` -> `coverage`
5. `Unit Tests` -> `tests`

### 4.2 Zestaw rozszerzony (jeśli dostępny)

1. `bugs`
2. `vulnerabilities`
3. `code_smells`
4. `duplicated_lines_density`
5. `sqale_rating` (maintainability)
6. `reliability_rating`
7. `security_rating`
8. `complexity`

Uwaga: metryki z sekcji `4.1` są wymagane; sekcja `4.2` jest opcjonalna i raportowana tam, gdzie dane są dostępne.

## 5. Plan techniczny (SonarQ API)

1. Uwierzytelnienie przez token w zmiennej środowiskowej (`SONAR_TOKEN`).
2. Endpointy robocze (do potwierdzenia na docelowej instancji SonarQ):
   - `/api/components/search_projects` (lista publicznych projektów)
   - `/api/projects/search` (wariant dla konkretnej organizacji)
   - `/api/measures/component`
   - `/api/measures/component_tree` (opcjonalnie)
3. Obsługa paginacji i limitów zapytań.
4. Retry/backoff dla błędów sieciowych i limitów.
5. Walidacja kompletności danych (braki metryk per projekt).

## 6. Artefakty PR

1. Skrypt pobierający i normalizujący dane benchmarkowe, np.:
   - `tools/sonar_market_benchmark.py`
2. Raport porównawczy:
   - `205B/analysis/205B_analiza_sonar_benchmark_rynek.md`
3. Dane surowe i przetworzone:
   - `205B/analysis/205B_analiza_sonar_benchmark_rynek.json`

## 7. Kryteria akceptacji

1. Benchmark obejmuje co najmniej `10` publicznych projektów.
2. Dla każdego projektu mamy komplet `5/5` metryk z sekcji `4.1`.
3. Dla metryk z sekcji `4.2` raportujemy pokrycie dostępności per metryka.
4. Raport zawiera pozycję `Venom` względem mediany i kwartylów benchmarku.
5. Proces jest powtarzalny (jedno polecenie uruchamia pełne odświeżenie danych).
6. Każda metryka w raporcie ma wskazane źródło i timestamp pobrania.

## 8. Ryzyka i ograniczenia

1. Niejednorodność projektów (różna skala i domena) może zniekształcać porównanie.
2. Część projektów publicznych może nie mieć pełnych metryk (np. brak coverage).
3. Różnice konfiguracji reguł SonarQ między projektami obniżają porównywalność.
4. Ograniczenia API/rate limit mogą wydłużać pobieranie danych.

## 9. Plan realizacji (proponowany)

1. Krok 1: lista projektów referencyjnych i kryteria doboru.
2. Krok 2: implementacja skryptu pobierającego dane z API.
3. Krok 3: walidacja jakości i kompletności datasetu.
4. Krok 4: raport `Venom vs rynek` + wnioski do pracy inżynierskiej.

## 10. Definition of Done

1. Nowy raport benchmarkowy i dataset istnieją w `205B`.
2. Skrypt benchmarku działa lokalnie i generuje identyczny format danych przy ponownym uruchomieniu.
3. Wnioski benchmarkowe mogą zostać bezpośrednio użyte w rozdziale analitycznym pracy końcowej.

## Produkty (co przedstawiają)

1. `205B/analysis/205B_analiza_sonar_benchmark_rynek.md`
   - raport benchmarku SonarQ (zakres, kompletność, wynik porównawczy).
2. `205B/analysis/205B_analiza_sonar_benchmark_rynek.json`
   - manifest i metadane uruchomienia benchmarku 205B.
3. `205B/timeseries/205B_timeseries_q1_2026.csv`
   - zbiorcza seria dzienna metryk SonarQ dla repo referencyjnych i Venom.
4. `205B/timeseries/raw/*.json`
   - surowe odpowiedzi i payloady per projekt.
5. `205B/timeseries/csv/*.csv`
   - dzienne serie per projekt gotowe do analizy tabelarycznej.
