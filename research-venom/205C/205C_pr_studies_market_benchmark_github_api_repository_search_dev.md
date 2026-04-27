# 205C - Benchmark rynkowy przez GitHub API: dobór repo i analiza Q1 2026

Data: `2026-04-22`  
Status: `planned`  
Priorytet: `P1`  
Powiązanie:
1. `205/205_pr_studies_ai_software_process_automation_git_code_analysis_dev.md`
2. `205B/205B_pr_studies_market_benchmark_sonar_api_problem_definition_dev.md`
3. `tools/205E_github_closed_pr_analysis.py`

## 0. Kontekst

Metodyka `205B` (SonarQ API) pokazała ograniczenia dostępności danych i heterogeniczność próby.
W `205C` dokładamy drugą, niezależną metodykę opartą o GitHub API.
Cel: znaleźć i przefiltrować repozytoria bardziej dopasowane do `Venom` pod kątem aktywności w `Q1 2026`, skali i technologii, a następnie policzyć metryki zmian w czasie.

## 1. Opis problemu (205C)

Problem do rozwiązania:
`Jak zbudować powtarzalny proces doboru aktywnych, publicznych repozytoriów przez GitHub Search API oraz policzyć porównywalne metryki aktywności i churn dla Q1 2026?`

## 2. Cel PR 205C

1. Zbudować pipeline selekcji repozytoriów przez GitHub Search API.
2. Zweryfikować aktywność repozytoriów w oknie `2026-01-01` -> `2026-03-31`.
3. Przygotować dataset i raport benchmarkowy `Venom vs rynek` oparty o metryki z GitHub.
4. Dostarczyć dane w formatach `JSON` (źródło) + `CSV` (transport do Excela).

## 3. Zakres PR

### 3.1 In-scope

1. Dobór kandydatów przez `/search/repositories` z kwalifikatorami:
   - `is:public`,
   - `archived:false`,
   - `fork:false` (domyślnie; opcjonalnie konfigurowalne),
   - `language:Python` (wariant A) lub język dowolny (wariant B),
   - `size` (KB) jako przybliżenie skali,
   - `pushed:2026-01-01..2026-03-31`.
2. Walidacja aktywności Q1 2026 przez `/repos/{owner}/{repo}/commits?since=...&until=...`.
3. Zbieranie metryk aktywności i zmian:
   - liczba commitów,
   - liczba aktywnych dni commitowych,
   - liczba autorów,
   - dodatki/usunięcia/churn,
   - liczba merged PR i wskaźniki komentarzy PR (opcjonalnie rozszerzenie).
4. Budowa rankingu repozytoriów referencyjnych (docelowo `10`) oraz raportu porównawczego.
5. Eksport danych:
   - per-repo (`JSON`, `CSV`),
   - agregat (`CSV`) do analizy statystycznej w Excel.

### 3.2 Out-of-scope

1. Bezpośrednie metryki Sonar (`Technical Debt`, `Coverage`, `Unit Tests`) z samego GitHub API.
2. Ręczna ocena merytoryczna jakości kodu każdego repo.
3. Długoterminowy monitoring po Q1 2026.

## 4. Analiza GitHub API (wnioski projektowe)

1. Search API zwraca maksymalnie `1000` wyników na pojedyncze zapytanie.
2. Search ma osobny limit: dla zapytań uwierzytelnionych do `30` req/min.
3. Search ma dodatkowe ograniczenia zakresu i czasu wykonania:
   - wyszukiwanie do określonego scope repo,
   - możliwe `incomplete_results=true` przy timeoutach.
4. Qualifiery repozytoriów (istotne dla doboru): `size`, `language`, `pushed`, `stars`, `forks`, `is:public`, `archived:false`, `org:`/`user:`.
5. Endpoint commitów obsługuje okna czasowe (`since`, `until`) i paginację (`per_page`, `page`) do walidacji aktywności kwartalnej.

## 5. Metodyka doboru próby

1. Etap A: kandydaci z Search API (filtry podstawowe).
2. Etap B: walidacja aktywności Q1 (commity w oknie czasu > 0).
3. Etap C: walidacja skali i jakości danych:
   - repo spełnia minimalny próg skali (`size` i/lub commit volume),
   - repo ma wystarczającą liczbę punktów aktywności w Q1,
   - repo nie jest projektem porzuconym przed Q1.
4. Etap D: finalna lista benchmarkowa (docelowo `10` repo).

## 6. Plan techniczny (skrypt 205C)

1. Nowy skrypt, np. `tools/205C_github_market_benchmark_q1.py`.
2. Uwierzytelnienie:
   - `gh auth token` (preferowane jak w istniejących skryptach),
   - fallback: `GITHUB_TOKEN`.
3. Warstwa API:
   - retry/backoff,
   - limity Search API,
   - kontrolowana paginacja.
4. Obsługa shardingu zapytań Search (redukcja ryzyka limitu 1000 wyników):
   - podział po przedziałach `stars` i/lub `size`,
   - deduplikacja wyników.
5. Eksport:
   - `JSON` surowy,
   - `CSV` per-repo,
   - `CSV` agregat.

## 7. Artefakty PR

1. Skrypt:
   - `tools/205C_github_market_benchmark_q1.py`
2. Raport selekcji repo:
   - `205C/selection/205C_repo_selection_github.md`
   - `205C/selection/205C_repo_selection_github.json`
3. Raport metryk benchmarkowych:
   - `205C/analysis/205C_analiza_github_benchmark_q1_2026.md`
   - `205C/analysis/205C_analiza_github_benchmark_q1_2026.json`
4. Dane tabelaryczne do Excela:
   - `205C/timeseries/205C_github_benchmark_q1_2026.csv`
   - `205C/timeseries/csv/*.csv`

## 8. Kryteria akceptacji

1. Pipeline dobiera i waliduje minimum `10` repozytoriów aktywnych w Q1 2026.
2. Każde repo ma policzone metryki aktywności/churn dla Q1 2026.
3. Eksport `JSON + CSV` działa deterministycznie przy ponownym uruchomieniu.
4. Raport jawnie opisuje kryteria selekcji i ograniczenia danych.
5. W raporcie jest porównanie `Venom` do mediany/przedziałów benchmarku.

## 9. Ryzyka i ograniczenia

1. Search API ma limit `1000` wyników na zapytanie i może zwracać niepełne wyniki.
2. `size` w GitHub Search to metryka repo (KB), nie bezpośrednio `LOC`.
3. Część projektów może mieć wysoką aktywność, ale inny profil domenowy niż Venom.
4. Różnice w strategii commitowania (squash/rebase/merge) wpływają na metryki commitowe.

## 10. Definition of Done

1. Powstaje nowy benchmark `205C` oparty wyłącznie o GitHub API.
2. Jest finalna lista `10` repo z walidacją aktywności Q1 2026.
3. Dane są gotowe do importu do Excela (`CSV`) i do archiwizacji źródłowej (`JSON`).
4. Raport `205C` dokumentuje metodę, ograniczenia i kluczowe wnioski porównawcze.

## 11. Źródła API

1. GitHub REST Search API (limity, 1000 wyników, rate limit search):
   - `https://docs.github.com/en/rest/search/search?apiVersion=2022-11-28`
2. GitHub repository search qualifiers (`size`, `language`, `pushed`, `is:public`, `archived`):
   - `https://docs.github.com/en/search-github/searching-on-github/searching-for-repositories`
3. GitHub REST commits endpoint (`since`, `until`, paginacja):
   - `https://docs.github.com/en/rest/commits/commits?apiVersion=2022-11-28`

## Produkty (co przedstawiają)

1. `205C/selection/205C_repo_selection_github.md`
   - raport doboru repo referencyjnych przez GitHub Search API.
2. `205C/selection/205C_repo_selection_github.json`
   - surowe dane selekcji i ranking kandydatów.
3. `205C/analysis/205C_analiza_github_benchmark_q1_2026.md`
   - raport porównawczy aktywności/churn Q1 2026.
4. `205C/analysis/205C_analiza_github_benchmark_q1_2026.json`
   - manifest metryk i summary per repo.
5. `205C/timeseries/205C_github_benchmark_q1_2026.csv`
   - zbiorcza seria dzienna metryk GitHub (Q1 2026).
6. `205C/timeseries/csv/*.csv`
   - serie dzienne per repo do Excela.
7. `205C/timeseries/raw/*.json`
   - surowe payloady per repo (commits i agregaty).
