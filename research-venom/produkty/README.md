# Produkty - seria 205

Ten katalog zawiera produkty pracy dyplomowej o procesie wytwórczym Venom.

## Podział

1. `word/final/`
   - produkt końcowy: dokument pracy (`.docx`) z tabelami i wykresami.
2. `excel/workspace/`
   - produkt pośredni: skoroszyt roboczy (`.xlsx`) z:
     - zakładkami źródłowymi (raw),
     - zakładkami przetworzonymi,
     - wykresami editable.
3. `excel/exports/`
   - eksporty pomocnicze (np. PNG wykresów do prezentacji).
4. `meta/`
   - metadane wersji produktów i notatki publikacyjne.

## Zasada

- `demo/` służy tylko do testów technicznych i PoC.
- Materiał finalny i roboczy do pracy utrzymujemy wyłącznie w `produkty/`.
- Nie nadpisujemy produktów: każda nowa iteracja dostaje nową wersję z sufiksem `_vNN`.

## Wersjonowanie nazw (obowiązkowe)

1. Wersje robocze:
   - `205F_visualization_workspace_v01.xlsx`
   - `205F_visualization_workspace_v02.xlsx`
2. Wersje dokumentu Word:
   - `Projekt_Koncowy_Pieniak_FINAL8_v01.docx`
   - `Projekt_Koncowy_Pieniak_FINAL8_v02.docx`
3. Eksporty wykresów:
   - `chart_205D_lead_time_v01.png`
   - `chart_205D_lead_time_v02.png`
