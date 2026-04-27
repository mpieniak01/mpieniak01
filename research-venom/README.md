# research-venom (scripts-only stage)

Ten etap publikuje wyłącznie warstwę narzędziową (bez danych badawczych i artefaktów binarnych).

## Zakres

- `research-venom/tools/` — skrypty ETL/automatyzacji serii 205
- `research-venom/config/` — konfiguracja i manifesty whitelist
- `research-venom/.gitignore` — reguły lokalne
- `/.github/workflows/scripts-review-ci.yml` — lekki CI dla skryptów
- `/.github/copilot-instructions.md` — instrukcje Copilot dla zakresu `research-venom`

## Poza zakresem tego PR

- dane timeseries (`205B/205C/205D/205E/...`),
- raporty analityczne i pliki robocze,
- produkty (`xlsx/docx/png`) i katalog `demo/`.

## Cel

Najpierw stabilizujemy i recenzujemy jakość skryptów.
Import danych/artefaktów badawczych będzie osobnym PR.
