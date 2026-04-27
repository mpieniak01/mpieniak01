# 205D PR Studies: PR Flow Efficiency (Git Local + GitHub API)

## 1. Problem badawczy
W zadaniach 205B i 205C została opisana dynamika zmian kodu (time series metryk jakości i aktywności), ale brakuje osobnej warstwy procesowej dotyczącej samego przepływu PR.
Celem 205D jest pomiar efektywności pipeline PR w Q1 2026 i przygotowanie wskaźników porównawczych względem danych już zebranych dla Venom.

## 2. Cel badania
- Zmierzyć intensywność procesu PR (ile PR otwierano i zamykano w czasie).
- Zmierzyć czas realizacji PR (od otwarcia do merge lub close).
- Wyznaczyć dzienne średnie i trend czasowy dla Q1 2026.
- Przygotować metryki możliwe do zestawienia z wynikami 205B/205C.

## 3. Zakres czasowy
- Okres bazowy: Q1 2026 (`2026-01-01` do `2026-03-31`).
- Raportowanie dzienne.
- Normalizacja dat do jednej strefy raportowej (Europe/Warsaw) przy liczeniu agregatów dziennych.

## 4. Źródła danych i warianty metody
- Wariant A (preferowany): GitHub API (pełny lifecycle PR: `created_at`, `merged_at`, `closed_at`, dane review).
- Wariant B (uzupełniający): lokalny Git (mirror) do walidacji wolumenu merge i aktywności gałęzi.
- Decyzja metodyczna: metryki czasu PR liczone z GitHub API, lokalny Git używany jako cross-check spójności.

## 5. Definicje metryk
- `pr_opened_count_daily`: liczba PR otwartych danego dnia.
- `pr_merged_count_daily`: liczba PR zmergowanych danego dnia.
- `pr_closed_not_merged_daily`: liczba PR zamkniętych bez merge danego dnia.
- `pr_active_daily`: liczba PR otwartych na koniec dnia.
- `pr_lead_time_hours`: czas od `opened_at` do `merged_at` (dla merged PR).
- `pr_review_latency_hours`: czas od `opened_at` do pierwszego review.
- `pr_daily_avg_lead_time`: średni lead time PR zmergowanych danego dnia.
- `pr_daily_median_lead_time`: mediana lead time PR zmergowanych danego dnia.
- `pr_size_proxy`: `commits`, `additions`, `deletions`, `changed_files`.
- `merge_rate_q1`: udział zmergowanych PR (`merged / opened`).
- `backlog_pressure_q1`: średnia wartość `pr_active_daily`.

## 6. Reguły klasyfikacji w Venom
- Do analizy bierzemy PR realizujące standardowy flow: branch -> PR -> review -> merge do `main`.
- PR typu draft:
  - liczony do wolumenu otwarć,
  - w analizie czasu opcjonalnie liczony od momentu `ready_for_review` (jeśli dane dostępne).
- PR zamknięte bez merge:
  - raportowane osobno,
  - nie wchodzą do metryk `lead_time` dla merged.
- PR ponownie otwierane:
  - traktowane jako jeden PR z finalnym stanem.
- Strategie merge (merge/squash/rebase):
  - klasyfikowane na podstawie `merged_at`, nie na podstawie samej struktury commitów lokalnych.

## 7. Artefakty danych
- JSON surowy per repo (PR + wymagane pola timeline/status).
- CSV dzienny per repo.
- CSV zbiorczy Q1 2026 (analogiczny do 205B/205C).
- Manifest JSON + podsumowanie MD z metrykami i ograniczeniami.

## 8. Wskaźniki końcowe do porównań
- Średnia dzienna liczba PR otwieranych i mergowanych.
- Średni i medianowy czas realizacji PR (godziny).
- Percentyle czasu realizacji (`P50`, `P75`, `P90`).
- `merge_rate_q1`.
- `backlog_pressure_q1`.

## 9. Ryzyka metodologiczne
- Limity API i ewentualne braki danych timeline dla części repo.
- Różne praktyki review/merge między projektami.
- Niejednorodny rozmiar PR (małe hotfixy vs duże PR) i wpływ na średnie.
- Wysoka intensywność Venom może wymagać raportowania mediany i percentyli obok średniej.

## 10. Kryteria akceptacji 205D
- Dla Venom powstaje dzienny dataset Q1 2026 PR flow (open/merge/close/time).
- Powstają metryki końcowe: `avg/median/P90 lead time`, `merge rate`, `backlog pressure`.
- Artefakty są spójne ze standardem 205B/205C (per-repo + aggregate + manifest).
- Metodyka rozróżnia merged i closed without merge.

## Produkty (co przedstawiają)

1. `205D/analysis/205D_analiza_pr_flow_q1_2026.md`
   - raport benchmarku PR flow Q1 2026 dla całej próbki repo.
2. `205D/analysis/205D_analiza_pr_flow_q1_2026.json`
   - manifest metodyki i KPI per repo.
3. `205D/timeseries/205D_pr_flow_q1_2026.csv`
   - zbiorcza seria dzienna PR flow (opened/merged/active/lead time).
4. `205D/timeseries/csv/*.csv`
   - serie dzienne PR flow per repo.
5. `205D/timeseries/raw/*.json`
   - surowe payloady PR flow per repo.
6. `205D/inputs/205D_repo_keys_selected.txt`
   - lista repo referencyjnych użyta do zbierania próby 205D.
