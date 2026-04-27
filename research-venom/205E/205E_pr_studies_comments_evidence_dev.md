# 205E - Uzupełnienie materiału dowodowego: komentarze PR (Venom)

## Cel

Dodać wskaźnik jakości procesu review, aby uzupełnić 205D o dowód, że PR nie były automatycznie otwierane i zamykane bez interakcji.

## Co zebrano dodatkowo

- `comments`, `review_comments`, `total_comments` per PR,
- agregację dzienną i podsumowanie Q1 2026 (średnia/mediana komentarzy).

## Jak zebrano

- wykorzystano istniejący dataset `205/analysis/205_analiza_pr.json` (GitHub API, PR zamknięte),
- filtrowanie do Q1 2026 po `closed_at`,
- obliczenia dla dwóch zakresów: `closed` i `merged`.

## Artefakty (Excel-ready)

- `205E_pr_comments_q1_2026_summary.csv`,
- `205E_pr_comments_q1_2026_daily.csv`,
- `205E_pr_comments_q1_2026_per_pr.csv`,
- `205E_analiza_pr_comments_q1_2026.json`,
- `205E_analiza_pr_comments_q1_2026.md`.

## Kryterium akceptacji

W raporcie 205D dostępny jest wskaźnik komentarzy PR (średnia i mediana), spójny metodycznie i gotowy do importu do Excela.

## Produkty (co przedstawiają)

1. `205E/timeseries/csv/205E_pr_comments_q1_2026_summary.csv`
   - podsumowanie Q1 2026: średnia/mediana komentarzy PR i udział zero-komentarzowych.
2. `205E/timeseries/csv/205E_pr_comments_q1_2026_daily.csv`
   - dzienne agregaty komentarzy PR (closed i merged).
3. `205E/timeseries/csv/205E_pr_comments_q1_2026_per_pr.csv`
   - pełna tabela per PR z polami komentarzy.
4. `205E/analysis/205E_analiza_pr_comments_q1_2026.json`
   - manifest obliczeń i statystyki końcowe.
5. `205E/analysis/205E_analiza_pr_comments_q1_2026.md`
   - raport opisowy wyników 205E.
