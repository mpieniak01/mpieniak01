# SESSION 205 Handoff v01

Data zapisu: 2026-04-27

## 1. Cel i bieżąca strategia publikacji

1. `205_artifacts` traktujemy jako niezależny projekt badawczy do publikacji w repo wizytówki.
2. Docelowe miejsce publikacji: `research-venom/` w `mpieniak01/mpieniak01`.
3. Publikacja wyłącznie whitelistą (manifest), bez kopiowania „całości jak leci”.
4. Dla recenzji skryptów używamy osobnego, wąskiego pakietu `scripts-review`.

## 2. Kluczowe decyzje

1. Struktura paczki jest spłaszczana:
   - `<...>` -> `research-venom/<...>`.
2. Do osadzania wykresów używany jest lekki Word canvas:
   - `produkty/word/final/205F_embed_canvas_v01.docx` -> `..._v02.docx`.
3. Pipeline 205F ma tryb nadzorczy:
   - `-StepTimeoutSec`
   - `-CleanupOfficeOrphans`
   - `-SkipBookmarkInsert` (praktyczny workaround niestabilnego `S06`).

## 3. Najważniejsze pliki konfiguracyjne

1. `config/205f_pipeline_config_v01.json`
2. `config/205_export_manifest_v01.txt` (pełna paczka)
3. `config/205_export_manifest_scripts_review_v01.txt` (wąska paczka)
4. `PR_205_REVIEW.md` (zakres recenzji)

## 4. CI i Copilot (do repo docelowego)

1. `.github/workflows/scripts-review-ci.yml`
2. `.github/copilot-instructions.md`
3. `.gitignore`

## 5. Status exportów (bez push/commit)

### Scripts-review

- Manifest: `config/205_export_manifest_scripts_review_v01.txt`
- Ostatni dry-run: 25 plików
- Zakres: root docs + config + tools + `.github` + `.gitignore` + `PR_205_REVIEW.md`
- Bez `205F/*` danych/speców

### Full whitelist

- Manifest: `config/205_export_manifest_v01.txt`
- Ostatni dry-run: 72 pliki
- Zakres: pełniejszy pakiet badawczy + produkty + analizy serii 205

## 6. Komendy robocze

### A. Podgląd paczki scripts-review

```bash
python3 /home/ubuntu/research-venom/tools/205f_export_research_pack.py \
  --manifest /home/ubuntu/research-venom/config/205_export_manifest_scripts_review_v01.txt \
  --dry-run
```

### B. Zbudowanie paczki scripts-review

```bash
python3 /home/ubuntu/research-venom/tools/205f_export_research_pack.py \
  --manifest /home/ubuntu/research-venom/config/205_export_manifest_scripts_review_v01.txt
```

### C. Podgląd pełnej paczki

```bash
python3 /home/ubuntu/research-venom/tools/205f_export_research_pack.py \
  --manifest /home/ubuntu/research-venom/config/205_export_manifest_v01.txt \
  --dry-run
```

## 7. Co zostało do decyzji

1. Który wariant publikować teraz:
   - `scripts-review` (rekomendowany na teraz),
   - czy `full whitelist`.
2. Czy zostawić `sonar_market_benchmark.py` w paczce recenzenckiej, czy tylko skrypty 205C/205D/205E/205F.

