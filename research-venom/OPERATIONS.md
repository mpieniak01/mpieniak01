# Operations - research-venom

## Current Mode: `scripts-only`

Repo jest ustawione na "hard ignore" dla danych i artefaktów badawczych.
Domyślnie śledzimy tylko:
- `research-venom/tools/`
- `research-venom/config/`
- `research-venom/README.md`
- `research-venom/PR_205_REVIEW.md`
- `research-venom/.gitignore`

## Why

To stabilizuje PR skryptowy i zapobiega przypadkowemu commitowaniu:
- dużych danych (`timeseries/raw/csv`),
- raportów roboczych,
- plików binarnych (`xlsx/docx/png`).

## How to publish research data later

1. Tymczasowo odblokuj śledzenie artefaktów:
   - usuń lub zakomentuj sekcję "Hard ignore" w `research-venom/.gitignore`.
2. Wygeneruj paczkę whitelistą:
   - `python research-venom/tools/205f_export_research_pack.py --manifest research-venom/config/205_export_manifest_v01.txt`
3. Sprawdź wynik i dopiero wtedy `git add` wybrane pliki.
4. Po publikacji przywróć `hard ignore`.

## Source of truth

- manifest pełny: `research-venom/config/205_export_manifest_v01.txt`
- manifest scripts-review: `research-venom/config/205_export_manifest_scripts_review_v01.txt`


## Current tree policy

- W gałęzi `scripts-only` katalog `research-venom/` ma zawierać tylko: `tools/`, `config/`, dokumenty root (`README.md`, `PR_205_REVIEW.md`, `OPERATIONS.md`, `.gitignore`).
- Katalogi serii (`205*`), `demo/`, `produkty/` są poza bieżącym zakresem i nie powinny występować lokalnie.
