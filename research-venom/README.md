# 205 Artifacts Layout

Cel: trzymać całą serię 205 (zarówno dokumenty zakresowe PR, jak i wyniki analiz oraz dane robocze) bezpośrednio w repo `research-venom`.

## Struktura

- `AGENTS.md`
  - reguły pracy podprojektu 205 (WSL/Windows, narzędzia, ścieżki, produkty)
- `produkty/`
  - główne produkty końcowe pracy (Word) i pośrednie produkty robocze (Excel)
- `tools/`
  - skrypty robocze serii 205 (uruchamiane z root repo)
- `205/`
  - `205_pr_studies_*` dokument zakresu PR 205
  - `analysis/` raporty i podsumowania dla 205
  - `inputs/` listy pomocnicze i dane wejściowe
- `205B/`
  - `205B_pr_studies_*` dokument zakresu PR 205B
  - `analysis/` raporty końcowe 205B
  - `screening/` wyniki screeningu kandydatów
  - `inputs/` listy kluczy projektów
  - `timeseries/` dane dzienne (`csv/`, `raw/`, aggregate)
- `205C/`
  - `205C_pr_studies_*` dokument zakresu PR 205C
  - `analysis/` raporty końcowe 205C
  - `selection/` wyniki doboru repo
  - `inputs/` listy repo
  - `timeseries/` dane dzienne (`csv/`, `raw/`, aggregate)
- `205D/`
  - `205D_pr_studies_*` dokument zakresu PR 205D
  - `analysis/` raporty i manifesty 205D
  - `inputs/` listy repo i dane wejściowe
  - `timeseries/` dane PR flow (`csv/`, `raw/`, aggregate)
- `205E/`
  - `205E_pr_studies_*` dokument zakresu PR 205E
  - `analysis/` raport i manifest 205E
  - `timeseries/` dane komentarzy PR (`csv/`)
- `205F/`
  - `205F_pr_studies_*` dokument zakresu PR 205F
  - `inputs/` specyfikacja wykresów i dane pomocnicze
  - `analysis/` raport i manifest wizualizacji
  - `products/` wynikowe artefakty (`excel/`, `charts/`)

## Zasada robocza

1. Nowe zadania PR dodajemy do `<seria>/`.
2. Wszystkie wygenerowane artefakty trafiają do `<seria>/...`.
3. W nazwach plików zachowujemy prefiks serii (`205`, `205B`, `205C`, `205D`, `205E`, `205F`).
4. Produkt główny pracy (DOCX) utrzymujemy w `produkty/word/final/`.
5. Produkt pośredni (Excel workspace) utrzymujemy w `produkty/excel/workspace/`.
6. Każde nowe przetworzenie zapisujemy jako nową wersję pliku z sufiksem `_vNN` (bez nadpisywania).
## Separacja Konfiguracji (pod przeniesienie do innego repo)

Pakiet 205 można traktować jako niezależny projekt badawczy (`research venom`).
Konfiguracja runtime i ścieżek nie jest rozproszona po skryptach, tylko trzymana centralnie:

- `config/205f_pipeline_config_v01.json`

W praktyce:
- przy migracji do nowego repo aktualizujesz przede wszystkim ten plik,
- `205f_run_pipeline.ps1` pobiera z niego ścieżki do workbook/docx/mapy i raportów,
- dla Word używamy lekkiego pliku `205F_embed_canvas_v01.docx` zamiast ciężkiego dokumentu końcowego.

## Decyzja Publikacyjna (Whitelist)

Decyzja dla serii 205:
1. Materiał publikujemy jako podkatalog `research-venom/` w repo wizytówki: `https://github.com/mpieniak01/mpieniak01`.
2. Publikacja NIE jest wykonywana przez kopiowanie całego `205_artifacts`.
3. Publikujemy wyłącznie przez białą listę (whitelist) z manifestu:
   - `config/205_export_manifest_v01.txt`
4. Paczkę publikacyjną budujemy skryptem:
   - `tools/205f_export_research_pack.py`
5. W paczce publikacyjnej stosujemy spłaszczanie ścieżek:
   - źródło: `<...>`
   - cel (repo wizytówki): `research-venom/<...>`
6. Pliki spoza manifestu (np. lokalne testy, surowe dumpy, pliki tymczasowe) nie są częścią publikacji.
7. Dla recenzji skryptów używamy artefaktu zakresowego:
   - `PR_205_REVIEW.md` (w głównym drzewie obok `README.md`).
