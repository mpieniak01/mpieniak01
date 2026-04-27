# 205 - Analiza kodu do pracy inżynierskiej: „Automatyzacja procesów wytwórstwa oprogramowania z wykorzystaniem AI”

Data: `2026-04-11`  
Status: `completed` (uzupełniono analizę jakościową, oś czasu oraz analizę zamkniętych PR z GitHub)  
Priorytet: `P1`  
Powiązanie:
1. `docs_dev/_to_do/204B_pr_workflow_control_target_screen_composition_step_activation_dev.md`
2. `docs_dev/_done/204_pr_workflow_control_real_state_runtime_control_alignment_dev.md`

## 0. Cel PR 205

Przygotować materiał analityczny do pracy na studia pod tytułem:
`Automatyzacja procesów wytwórstwa oprogramowania z wykorzystaniem AI`.

Materiał ma pokazać, ile kodu i zmian powstało w projekcie `Venom` w dwóch zdefiniowanych fazach:
1. Etap I: `2025-12-06` -> `2026-01-25`,
2. Etap II: `2026-02-06` -> `2026-03-06`.

## 1. Zakres PR

### 1.1 In-scope
1. Zdefiniowanie metodyki liczenia metryk z `git`.
2. Zestawienie metryk per etap:
   - liczba commitów,
   - liczba autorów,
   - liczba aktywnych dni commitowych,
   - liczba unikalnych plików dotkniętych zmianami,
   - sumy linii `added`, `deleted`, `net`.
3. Rozbicie zmian po:
   - rozszerzeniach plików,
   - top-level katalogach.
4. Syntetyczne porównanie Etap I vs Etap II.
5. Analiza zamkniętych PR z GitHub (`https://github.com/mpieniak01/Venom/pulls?state=closed`) z raportem szczegółowym.

### 1.2 Out-of-scope
1. Ocena jakości kodu (bug density, maintainability index, cyclomatic complexity).
2. Analiza issue tracker / PR review time.
3. Automatyczna klasyfikacja „AI-generated vs human-authored” na poziomie linii kodu.

### 1.3 Rozszerzenie zakresu (205B): analiza PR z GitHub
1. Przygotować skrypt pobierający zamknięte PR z API GitHub z paginacją i ochroną limitów.
2. Dla każdego PR zebrać:
   - tytuł (`title`),
   - opis (`body`),
   - skalę zmian linii (`additions + deletions`),
   - datę realizacji (`merged_at` lub `closed_at`),
   - liczbę komentarzy (`comments + review_comments`).
3. Wygenerować podsumowanie i pełny zakres danych do nowego pliku:
   - `205/analysis/205_analiza_pr.md`
   - (dane surowe) `205/analysis/205_analiza_pr.json`.

## 2. Metodyka

1. Źródło danych: historia `git` lokalnego repo `venom` na gałęzi `main`.
2. Okna czasowe liczone inkluzywnie (pełne dni):
   - Etap I: od `2025-12-06 00:00:00` do `2026-01-25 23:59:59`,
   - Etap II: od `2026-02-06 00:00:00` do `2026-03-06 23:59:59`.
3. Metryki zmian linii liczone z `git log --numstat` jako suma wszystkich commitów w oknie.
4. `files_changed_entries` oznacza liczbę wpisów zmian plików w commitach (churn entries), nie liczbę unikalnych plików.
5. Liczba unikalnych plików liczona oddzielnie na podstawie `--name-only` + `sort -u`.
6. `Gałęzie wydane` liczone jako merge commit `PR` na `main` (`git log --first-parent --merges` + tytuł `Merge pull request #...`).
7. `Wskaźnik poprawek przed mergem` liczony jako liczba commitów wniesionych przez gałąź PR przed scaleniem:
   - dla merge commit `M`: `git rev-list --count M^1..M^2`,
   - raportowane: `suma`, `średnia`, `mediana`, `p90`, `max`.

## 3. Dane (wyniki policzone)

### 3.1 Metryki główne per etap

| Metryka | Etap I (`2025-12-06` - `2026-01-25`) | Etap II (`2026-02-06` - `2026-03-06`) |
|---|---:|---:|
| Długość etapu (dni kalendarzowe) | 51 | 29 |
| Commity | 896 | 1222 |
| Autorzy (unikalni) | 4 | 5 |
| Aktywne dni commitowe | 33 | 29 |
| Unikalne pliki dotknięte zmianą | 1188 | 1528 |
| `files_changed_entries` (`numstat`) | 3936 | 5989 |
| Scalone PR-y (`gałęzie wydane`) | 104 | 104 |
| Unikalne gałęzie źródłowe PR | 103 | 103 |
| Linie dodane (`+`) | 267691 | 337036 |
| Linie usunięte (`-`) | 59640 | 132029 |
| Bilans netto (`+/-`) | 208051 | 205007 |

### 3.2 Wskaźniki intensywności

| Metryka | Etap I | Etap II |
|---|---:|---:|
| Śr. commitów / dzień kalendarzowy | 17.57 | 42.14 |
| Śr. linii dodanych / dzień | 5248.84 | 11621.90 |
| Śr. bilansu netto / dzień | 4079.43 | 7069.21 |
| Śr. commitów / aktywny dzień | 27.15 | 42.14 |
| Śr. PR / dzień kalendarzowy | 2.04 | 3.59 |
| Udział churn z gałęzi PR (add+del) | 77.61% | 65.45% |

### 3.3 Metryki gałęzi i wskaźnik poprawek przed mergem

| Metryka | Etap I | Etap II |
|---|---:|---:|
| Merge commit (first-parent) | 104 | 108 |
| Merge PR (`Merge pull request`) | 104 | 104 |
| Merge nie-PR | 0 | 4 |
| Commity na gałęziach PR przed mergem (suma) | 659 | 714 |
| Wskaźnik poprawek: średnia commitów/PR przed mergem | 6.34 | 6.87 |
| Wskaźnik poprawek: mediana commitów/PR przed mergem | 6.00 | 5.00 |
| Wskaźnik poprawek: p90 commitów/PR przed mergem | 8.50 | 13.50 |
| Wskaźnik poprawek: max commitów/PR przed mergem | 43 | 55 |

Interpretacja robocza:
1. W obu etapach większość zmian przechodziła przez PR/gałęzie feature (`104` merge PR w każdym etapie).
2. Etap II ma wyższy „ogon” poprawek przed mergem (`p90=13.50` vs `8.50`), co sugeruje większą zmienność wielkości gałęzi i częstsze większe paczki poprawek.
3. Udział churn z gałęzi PR jest nadal dominujący, ale niższy w Etapie II (`65.45%`) niż w Etapie I (`77.61%`).

### 3.4 Rozkład zmian po rozszerzeniach (Top 8 wg linii dodanych)

#### Etap I

| Rozszerzenie | + | - | Net |
|---|---:|---:|---:|
| `py` | 128838 | 19730 | 109108 |
| `md` | 60480 | 11569 | 48911 |
| `tsx` | 34058 | 17372 | 16686 |
| `json` | 11631 | 2719 | 8912 |
| `ts` | 10010 | 491 | 9519 |
| `js` | 5643 | 767 | 4876 |
| `html` | 5517 | 1623 | 3894 |
| `css` | 4308 | 376 | 3932 |

#### Etap II

| Rozszerzenie | + | - | Net |
|---|---:|---:|---:|
| `py` | 161047 | 44516 | 116531 |
| `json` | 62845 | 34144 | 28701 |
| `ts` | 47290 | 14754 | 32536 |
| `tsx` | 26155 | 15527 | 10628 |
| `md` | 24410 | 15200 | 9210 |
| `yaml` | 5474 | 5235 | 239 |
| `sh` | 2617 | 262 | 2355 |
| `txt` | 1885 | 1093 | 792 |

### 3.5 Rozkład zmian po top-level katalogach (Top 6 wg linii dodanych)

#### Etap I

| Katalog / ścieżka top-level | + | - | Net |
|---|---:|---:|---:|
| `venom_core` | 83093 | 17094 | 65999 |
| `web-next` | 54346 | 19035 | 35311 |
| `docs` | 51094 | 11075 | 40019 |
| `tests` | 39881 | 2095 | 37786 |
| `web` | 14656 | 3416 | 11240 |
| `examples` | 5059 | 317 | 4742 |

#### Etap II

| Katalog / ścieżka top-level | + | - | Net |
|---|---:|---:|---:|
| `web-next` | 77876 | 31898 | 45978 |
| `tests` | 77747 | 10531 | 67216 |
| `venom_core` | 72360 | 33231 | 39129 |
| `data` | 30269 | 30269 | 0 |
| `openapi` | 24215 | 2629 | 21586 |
| `docs` | 16832 | 7231 | 9601 |

### 3.6 Profil autorów (commity)

#### Etap I
1. `copilot-swe-agent[bot]`: `539`
2. `MPieniak`: `354`
3. `root`: `2`
4. `Ubuntu`: `1`

#### Etap II
1. `MPieniak`: `991`
2. `copilot-swe-agent[bot]`: `224`
3. `Venom CI`: `4`
4. `openai-code-agent[bot]`: `2`
5. `Ubuntu`: `1`

### 3.7 Analiza jakościowa: hotspoty zmian i ryzyko regresji

#### Etap I: Top 10 hotspotów plikowych (wg churn = `add+del`)

| Plik | + | - | Churn | Touches (liczba commitów dotykających plik) |
|---|---:|---:|---:|---:|
| `web-next/components/cockpit/cockpit-home.tsx` | 9413 | 8211 | 17624 | 45 |
| `web-next/package-lock.json` | 9114 | 936 | 10050 | 11 |
| `venom_core/core/orchestrator.py` | 4208 | 4165 | 8373 | 77 |
| `web-next/app/page.tsx` | 3719 | 3710 | 7429 | 18 |
| `web/static/css/app copy.css` | 2409 | 4818 | 7227 | 3 |
| `:memory:` | 3293 | 3293 | 6586 | 10 |
| `venom_core/core/orchestrator/orchestrator_core.py` | 2780 | 2146 | 4926 | 15 |
| `web/static/js/app.js` | 4350 | 562 | 4912 | 46 |
| `venom_core/main.py` | 2855 | 1756 | 4611 | 78 |
| `package-lock.json` | 1707 | 1707 | 3414 | 2 |

#### Etap II: Top 10 hotspotów plikowych (wg churn = `add+del`)

| Plik | + | - | Churn | Touches (liczba commitów dotykających plik) |
|---|---:|---:|---:|---:|
| `data/test_session_handler.json` | 16228 | 16228 | 32456 | 5 |
| `data/test_state_pruning.json` | 14008 | 14008 | 28016 | 5 |
| `openapi/openapi.json` | 24215 | 2629 | 26844 | 5 |
| `web-next/lib/generated/api-types.d.ts` | 21040 | 3881 | 24921 | 7 |
| `venom_core/api/routes/academy.py` | 6396 | 5541 | 11937 | 69 |
| `config/testing/test_catalog.yaml` | 5235 | 5234 | 10469 | 3 |
| `config/testing/test_catalog.json` | 5561 | 98 | 5659 | 22 |
| `venom_core/api/routes/academy_models.py` | 2367 | 2017 | 4384 | 20 |
| `venom_core/api/routes/system_llm.py` | 2852 | 916 | 3768 | 36 |
| `web-next/package-lock.json` | 2624 | 1119 | 3743 | 24 |

#### Wskaźniki ryzyka regresji (proxy na podstawie churn i częstotliwości zmian)

| Metryka ryzyka | Etap I | Etap II |
|---|---:|---:|
| Udział churn Top 1 pliku | 5.25% | 6.91% |
| Udział churn Top 3 plików | 10.74% | 18.58% |
| Udział churn Top 10 plików | 22.38% | 32.39% |
| Liczba plików z `touches >= 20` | 18 | 35 |
| Liczba plików z `touches >= 50` | 3 | 8 |

Wnioski jakościowe:
1. Etap II ma wyższą koncentrację zmian w małej grupie plików (`Top 10 share: 32.39%` vs `22.38%`), co podnosi ryzyko regresji lokalnych.
2. Etap II ma też większą liczbę plików intensywnie modyfikowanych (`touches >= 20`), co zwiększa ryzyko konfliktów i efektów ubocznych.
3. Najbardziej ryzykowne obszary funkcjonalne w Etapie II to:
   - kontrakty/API (`openapi/openapi.json`, `api-types.d.ts`),
   - backend Academy/LLM (`venom_core/api/routes/academy*.py`, `system_llm.py`),
   - katalogi danych testowych (`data/*.json`), które generują duży churn.

### 3.8 Oś czasu zmian (tygodniowa i miesięczna)

#### Etap I: agregacja tygodniowa

| Tydzień (ISO) | Commity | + | - | Net |
|---|---:|---:|---:|---:|
| `2025-W49` | 209 | 52807 | 3939 | 48868 |
| `2025-W50` | 357 | 108047 | 15037 | 93010 |
| `2025-W51` | 123 | 44770 | 12829 | 31941 |
| `2025-W52` | 29 | 8259 | 11593 | -3334 |
| `2026-W01` | 90 | 15293 | 6198 | 9095 |
| `2026-W02` | 52 | 20528 | 1873 | 18655 |
| `2026-W03` | 21 | 6165 | 4166 | 1999 |
| `2026-W04` | 15 | 15095 | 9140 | 5955 |

#### Etap II: agregacja tygodniowa

| Tydzień (ISO) | Commity | + | - | Net |
|---|---:|---:|---:|---:|
| `2026-W06` | 252 | 51991 | 41292 | 10699 |
| `2026-W07` | 419 | 81784 | 31796 | 49988 |
| `2026-W08` | 188 | 82248 | 21412 | 60836 |
| `2026-W09` | 218 | 83908 | 29575 | 54333 |
| `2026-W10` | 145 | 37693 | 8223 | 29470 |

#### Etap I: agregacja miesięczna

| Miesiąc | Commity | + | - | Net |
|---|---:|---:|---:|---:|
| `2025-12` | 788 | 225966 | 47226 | 178740 |
| `2026-01` | 108 | 44998 | 17549 | 27449 |

#### Etap II: agregacja miesięczna

| Miesiąc | Commity | + | - | Net |
|---|---:|---:|---:|---:|
| `2026-02` | 1051 | 282699 | 116795 | 165904 |
| `2026-03` | 171 | 54925 | 15503 | 39422 |

## 4. Syntetyczne porównanie Etap I vs Etap II

1. Etap II był krótszy (`29` vs `51` dni), ale miał większą intensywność pracy (`1222` vs `896` commitów).
2. Bilans netto linii kodu był zbliżony (`205007` vs `208051`), co sugeruje podobną skalę przyrostu funkcjonalnego.
3. W Etapie II wyraźnie wzrosła dynamika zmian w `web-next`, `tests` i `openapi`.
4. W Etapie I większy udział miały zmiany dokumentacyjne (`md`) i rozbudowa rdzenia (`venom_core`).
5. Etap II wykazuje wyższe ryzyko regresji z perspektywy koncentracji zmian (wyższy udział churn w Top 3/Top 10 hotspotach).
6. Największe tempo zmian przypadało na:
   - Etap I: `2025-W50`,
   - Etap II: `2026-W07` do `2026-W09`.

## 5. Komendy odtwarzające (reproducibility)

```bash
git log --since='2025-12-06 00:00:00' --until='2026-01-25 23:59:59' --pretty=tformat: --numstat
git log --since='2026-02-06 00:00:00' --until='2026-03-06 23:59:59' --pretty=tformat: --numstat
git rev-list --count --since='2025-12-06 00:00:00' --until='2026-01-25 23:59:59' HEAD
git rev-list --count --since='2026-02-06 00:00:00' --until='2026-03-06 23:59:59' HEAD
git shortlog -sne --since='2025-12-06 00:00:00' --until='2026-01-25 23:59:59' HEAD
git shortlog -sne --since='2026-02-06 00:00:00' --until='2026-03-06 23:59:59' HEAD
git log --first-parent --merges --since='2025-12-06 00:00:00' --until='2026-01-25 23:59:59' --pretty='%H %s'
git log --first-parent --merges --since='2026-02-06 00:00:00' --until='2026-03-06 23:59:59' --pretty='%H %s'
# dla pojedynczego merge commit M (wskaźnik poprawek przed mergem):
git rev-list --count M^1..M^2
# analiza zamkniętych PR z GitHub:
./tools/205E_github_closed_pr_analysis.py \
  --owner mpieniak01 \
  --repo Venom \
  --max-prs 3000 \
  --output-json 205/analysis/205_analiza_pr.json \
  --output-md 205/analysis/205_analiza_pr.md
```

## 5A. Wynik rozszerzenia 205B (analiza PR GitHub)

Artefakty:
1. `205/analysis/205_analiza_pr.md`
2. `205/analysis/205_analiza_pr.json`
3. `tools/205E_github_closed_pr_analysis.py`

Wynik główny (`mpieniak01/Venom`, PR zamknięte):
1. `313` zamkniętych PR (`299` merged, `14` closed without merge),
2. zakres dat: `2025-12-06` -> `2026-03-22`,
3. churn łączny: `1,036,591` linii (`+828,333` / `-208,258`),
4. komentarze łącznie: `3,847`,
5. średni churn/PR: `3,311.79`, mediana: `1,424`.

## 6. Checklista realizacji PR 205

1. `[DONE]` Zdefiniowano zakres i metodykę.
2. `[DONE]` Policzone metryki etapowe na podstawie `git`.
3. `[DONE]` Dodane zestawienia tabelaryczne do wykorzystania w pracy.
4. `[DONE]` Rozszerzenie o analizę jakościową (hotspoty zmian, ryzyko regresji).
5. `[DONE]` Rozszerzenie o oś czasu tygodniową/miesięczną do rozdziału wynikowego pracy.
6. `[DONE]` Rozszerzenie 205B: skrypt analizy zamkniętych PR z GitHub (paginacja + rate-limit guard).
7. `[DONE]` Wygenerowano `205_analiza_pr.md` i `205/analysis/205_analiza_pr.json` z danymi PR (title/body/line changes/realization date/comments).

## Produkty (co przedstawiają)

1. `205/analysis/205_analiza_pr.md`
   - raport jakościowy i statystyczny zamkniętych PR Venom.
2. `205/analysis/205_analiza_pr.json`
   - surowy dataset PR (per PR: daty, churn, komentarze, metadane).
3. `tools/205E_github_closed_pr_analysis.py`
   - skrypt odtwarzający pobranie i agregację danych PR.
