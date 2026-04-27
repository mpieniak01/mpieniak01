# 205_analiza_pr - Analiza zamkniętych PR (mpieniak01/Venom)

Data generacji: `2026-04-12T07:30:47Z`

## Zakres i metodyka

1. Źródło: GitHub REST API (`/repos/{owner}/{repo}/pulls?state=closed`).
2. Skrypt: `tools/205E_github_closed_pr_analysis.py` z paginacją (`per_page=100`) i retry/rate-limit guard.
3. Dla każdego PR zebrano: `title`, `body`, `line_changes (add+del)`, `realization_date (merged_at/closed_at)`, `comments + review_comments`.
4. Pełny dataset: `205_analiza_pr.json`.

## Wyniki główne

| Metryka | Wartość |
|---|---:|
| Zamknięte PR | 313 |
| Merged PR | 299 |
| Closed bez merge | 14 |
| Zakres dat closed | 2025-12-06 -> 2026-03-22 |
| Suma linii dodanych | 828333 |
| Suma linii usuniętych | 208258 |
| Suma zmian linii (churn) | 1036591 |
| Suma komentarzy (issue + review) | 3847 |
| Śr. churn / PR | 3311.79 |
| Mediana churn / PR | 1424 |
| Śr. komentarzy / PR | 12.29 |
| Mediana komentarzy / PR | 9 |

## Rozkład miesięczny (closed PR)

| Miesiąc | Zamknięte PR |
|---|---:|
| `2025-12` | 111 |
| `2026-01` | 36 |
| `2026-02` | 120 |
| `2026-03` | 46 |

## Tematy dominujące (heurystyka słów kluczowych)

| Temat | Liczba PR |
|---|---:|
| `backend_api` | 265 |
| `tests_quality` | 264 |
| `frontend_ui` | 223 |
| `models_ai` | 195 |
| `docs` | 175 |
| `infra_devops` | 156 |
| `security` | 156 |

## Najczęstsze słowa (title+body)

| Słowo | Wystąpienia |
|---|---:|
| `venom_core` | 1471 |
| `api` | 1259 |
| `tests` | 1156 |
| `copilot` | 1003 |
| `agent` | 880 |
| `test` | 758 |
| `web-next` | 668 |
| `coding` | 661 |
| `nie` | 639 |
| `make` | 632 |
| `start` | 574 |
| `pass` | 519 |
| `details` | 507 |
| `core` | 503 |
| `docs` | 502 |

## Top 15 PR wg skali zmian linii

| PR | Tytuł | Linie zmian | Komentarze | Data realizacji |
|---:|---|---:|---:|---|
| [#461](https://github.com/mpieniak01/Venom/pull/461) | PR 203: Cockpit ONNX runtime/model contract alignment | 209165 | 11 | `2026-03-15` |
| [#281](https://github.com/mpieniak01/Venom/pull/281) | Feat/123 sonar maintainability batch | 38455 | 2 | `2026-02-08` |
| [#388](https://github.com/mpieniak01/Venom/pull/388) | feat(api): finalize architecture cleanup and generated contract migration | 32181 | 2 | `2026-02-21` |
| [#243](https://github.com/mpieniak01/Venom/pull/243) | Feat/095 refaktoryzacja architektury | 24509 | 36 | `2026-01-27` |
| [#155](https://github.com/mpieniak01/Venom/pull/155) | Add Next.js migration plan | 21854 | 18 | `2025-12-16` |
| [#278](https://github.com/mpieniak01/Venom/pull/278) | Task/120 api response contracts | 16971 | 9 | `2026-02-08` |
| [#153](https://github.com/mpieniak01/Venom/pull/153) | docs(ui): add agent contract for UI refactor | 16724 | 5 | `2025-12-16` |
| [#415](https://github.com/mpieniak01/Venom/pull/415) | PR 183 follow-up: publish pending architecture decomposition backlog | 15979 | 7 | `2026-03-01` |
| [#361](https://github.com/mpieniak01/Venom/pull/361) | hotfix: domknięcie 150a/150b (workflow runtime UI + kontrakt API BE/FE) | 13556 | 10 | `2026-02-16` |
| [#362](https://github.com/mpieniak01/Venom/pull/362) | 151 feat(api-map): Implement Dynamic API Map + UI fixes | 13167 | 14 | `2026-02-16` |
| [#270](https://github.com/mpieniak01/Venom/pull/270) | Task 112: Visual Lift & Coverage Improvement (+ Pre-commit fixes) | 13095 | 5 | `2026-02-06` |
| [#268](https://github.com/mpieniak01/Venom/pull/268) | Fix/dashboard sorting utc | 12510 | 16 | `2026-02-06` |
| [#465](https://github.com/mpieniak01/Venom/pull/465) | 204B: domknięcie graph-first workflow-control + kontrakty | 12009 | 4 | `2026-03-22` |
| [#264](https://github.com/mpieniak01/Venom/pull/264) | Remove legacy Jinja2 UI in favor of Next.js frontend | 11751 | 1 | `2026-02-04` |
| [#231](https://github.com/mpieniak01/Venom/pull/231) | Complete English documentation translation (76% → 100%, 42→55 files) | 11060 | 0 | `2026-01-08` |

## Podsumowanie

1. Repo ma dużą bazę zamkniętych PR; skala zmian jest wysoka, a mediana churn na PR istotnie niższa od średniej (rozkład z długim ogonem dużych PR).
2. Dominują obszary: backend/API, frontend/UI, testy/jakość oraz modele/AI, co jest spójne z ewolucją produktu i stabilizacją jakości.
3. Dla pracy inżynierskiej można wykorzystać: trend miesięczny, top PR wg churn oraz relację `churn <-> komentarze` jako wskaźnik złożoności zmian.

