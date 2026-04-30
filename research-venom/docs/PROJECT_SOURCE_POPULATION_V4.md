# PROJECT SOURCE POPULATION V4

Dokument wyjaśnia, ile projektów znajduje się w źródłach `v04` i ile z nich jest pokazywanych na wykresach.

## Źródła Surowe

| Źródło | Tabela | Liczba projektów | Znaczenie |
|---|---:|---:|---|
| GitHub API benchmark | `src_205C_timeseries` | 11 | repozytoria GitHub do metryk commitów i zmian kodu |
| GitHub PR flow | `src_205D_timeseries` | 11 | te same repozytoria GitHub do metryk PR |
| SonarCloud API | `src_205B_timeseries` | 11 | osobny zbiór projektów SonarCloud do jakości i długu |
| GitHub PR comments | `src_205E_daily` | 1 | tylko `mpieniak01/Venom` dla komentarzy PR |

GitHub i SonarCloud nie są tą samą populacją projektów. GitHub używa kluczy repozytoriów `owner/repo`, a SonarCloud używa kluczy projektów Sonar, np. `mpieniak01_Venom`.

## Reguła Prezentacji

W `v04` liczba projektów pokazywanych na wykresie ma być jawna:

| Zakres wykresów | Źródło | Pokazywane projekty |
|---|---|---:|
| `W31`, `W32` | GitHub API benchmark | 11 |
| `W36` | SonarCloud API | 11 |
| `W37`, `W35`, `W42`, `W43` | SonarCloud API | 1, tylko Venom |
| `W33` | GitHub API benchmark | 1, tylko Venom |
| `WP1`-`WP4` | GitHub PR flow | 11 |
| `WP5`, `WP6` | GitHub PR flow | 1, tylko Venom |

Wcześniejsza konfiguracja `comparison_peer_group_size=6` ograniczała `WP1`-`WP4` do Venom plus pięciu projektów kontekstowych. To było mylące, bo dane wejściowe PR flow zawierały 11 repozytoriów. W `v04` aktywny kontrakt pokazuje pełną populację 11 repozytoriów.

## Kontrakt Arkuszy

`source_type` steruje domenowym stylem arkusza i musi zgadzać się ze źródłem danych:

| `source_type` | Kiedy używać |
|---|---|
| `github` | `src_205C_timeseries` i tabele z GitHub API benchmark |
| `sonarqube` | `src_205B_timeseries` i tabele SonarCloud |
| `git_prflow` | `src_205D_timeseries` i tabele PR flow |

Ten kontrakt jest sprawdzany w `tests/test_visualization_phase_contract.py`.

## Blokady Regresji

Te reguły są częścią stabilnego kontraktu `v04`:

1. `WP1`-`WP4` pokazują 11 repozytoriów PR flow, nie 6.
2. `comparison_peer_group_size=6` pozostaje tylko historycznym zachowaniem `v03`; nie wolno go przenosić do aktywnego `v04` bez nowej decyzji metodologicznej.
3. W opisach arkuszy i chartów trzeba rozróżniać:
   - liczbę projektów wejściowych,
   - liczbę projektów renderowanych,
   - domenę danych.
4. GitHub API benchmark i GitHub PR flow mogą mieć te same repozytoria, ale są różnymi tabelami źródłowymi i różnymi metodykami metryk.
5. SonarCloud używa osobnych kluczy projektów i nie powinien być opisywany jako GitHub API.

Pełny kontrakt antyregresyjny jest w [VISUALIZATION_V4_STABILITY_CONTRACT](VISUALIZATION_V4_STABILITY_CONTRACT.md).
