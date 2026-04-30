# RELEASE CHECKLIST

Checklista przygotowania `research-venom` do publikacji na GitHub.

## 1. Quality Gate

1. `make test-contracts`
2. `make test-contracts-ci`
3. `make test-contracts-local-real` (wymaga prywatnego local config)
4. `make test-static`
5. `make test-powershell-parse`
6. Potwierdzenie spójności aktywnego kontraktu `v04` w:
   - `config/process_pipeline_v04.json`
   - `README.md`
   - `.github/workflows/scripts-review-ci.yml`

Kryterium akceptacji:

1. `0` failed tests.
2. `0` niespójności wersji kontraktu (`v04` jest aktywne).
3. `0` naruszeń kontraktu trybów wejścia:
   - CI = sample inputs,
   - local real = real inputs.

## 2. Security Gate

Lokalnie (pre-release):

1. `gitleaks detect --source . --no-git --verbose`
2. `python -m pip_audit --progress-spinner off`
3. `bandit -q -r tools -ll`

W CI:

1. `Security Gate` workflow przechodzi:
   - gitleaks,
   - pip-audit,
   - bandit,
   - PSScriptAnalyzer,
   - CodeQL (Python).

Kryterium akceptacji:

1. `0` high/critical security findings.
2. Brak sekretów i danych wrażliwych w repo.

## 3. Publication Contract

Publiczny release zawiera:

1. `tools/`, `config/`, `tests/`, `docs/`, `.github/`, `Makefile`, `README.md`.
2. Tylko lekkie wejścia `artifacts/inputs/**` jako część kontraktu produktu.

Poza publicznym zakresem release:

1. `artifacts/sources/**`
2. `artifacts/processing/**`
3. `artifacts/products_light/**` (poza ewentualnymi ręcznie wskazanymi raportami)
4. `artifacts/meta/**`
5. `_external/not_tracked/**`

Kryterium akceptacji:

1. Czysty clone repo pozwala uruchomić `make test-contracts` bez prywatnych danych.
2. Brak ciężkich runtime outputs (`.xlsx`, `.docx`, `.png`) w commitach publikacyjnych.

## 4. Review Readiness

1. PR opisuje zakres: co zmieniono, czego świadomie nie publikujemy.
2. PR zawiera dowody z testów lokalnych i CI.
3. PR potwierdza, że fetch danych API jest jawny (`CONFIRM_API=1`) i nie jest uruchamiany w CI.
4. PR potwierdza separację: `fetch` vs `process` vs `product`.

## 5. Known Limits

1. Kroki Excel/Word wymagają Windows Office COM (`powershell.exe` z hosta Windows).
2. CI publiczne nie uruchamia produktu Office COM, tylko testy kontraktowe, statyczne i security.
3. Metryki produktu wymagające danych prywatnych pozostają poza publicznym repo i poza publicznym CI.
