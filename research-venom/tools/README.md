# 205 Tools

Skrypty robocze dla serii badawczej 205 zostały wydzielone z `scripts/ops` do tego katalogu,
żeby oddzielić kod produkcyjny Venom od narzędzi analitycznych pracy dyplomowej.

## Zasada

1. Skrypty 205 uruchamiamy z root repo, np.:
   - `python3 tools/sonar_market_benchmark.py`
   - `python3 tools/205C_github_market_benchmark_q1.py`
   - `python3 tools/205D_github_pr_flow_q1.py`
   - `python3 tools/205E_github_closed_pr_analysis.py`
2. Domyślne ścieżki wejścia/wyjścia są ustawione na strukturę `...`.
3. Sekrety pozostają w `.env.dev` (`GITHUB_TOKEN`, `SONAR_TOKEN`) i nie są kopiowane do artefaktów.
4. Konwencja nazw dla skryptów serii 205: `205<ETAP>_<obszar>_<cel>.py` (np. `205D_github_pr_flow_q1.py`).

## 205F Pipeline (Office Guard)

Do pipeline 205F używamy:
- `tools/205f_run_pipeline.ps1`
- lekki nośnik Word (canvas): `tools/205f_word_create_embed_canvas.ps1`

Uwaga operacyjna:
- nie osadzamy wykresów bezpośrednio do 55-stronicowego dokumentu źródłowego,
- osadzanie robimy na lekkim pliku `205F_embed_canvas_v01.docx` -> `205F_embed_canvas_v02.docx`.
- ustawienia pipeline i ścieżek trzymamy w centralnym configu:
  - `config/205f_pipeline_config_v01.json`

Parametry nadzorcze:
- `-StepTimeoutSec <sekundy>`: limit czasu na pojedynczy krok (fail-fast),
- `-CleanupOfficeOrphans`: po każdym kroku zamyka osierocone procesy `WINWORD/EXCEL` uruchomione przez pipeline.
- `-SkipBookmarkInsert`: pomija `S06` (bookmark insert), ale zostawia `S07/S09`; przydatne gdy bookmarki już istnieją i `S06` jest niestabilny.

Przykłady:
- tylko Excel/verify (bez Word):
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...\\205f_run_pipeline.ps1 -SkipWord -CleanupOfficeOrphans -StepTimeoutSec 300`
- pełny przebieg:
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...\\205f_run_pipeline.ps1 -CleanupOfficeOrphans -StepTimeoutSec 600`
- pełny przebieg bez `S06`:
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...\\205f_run_pipeline.ps1 -CleanupOfficeOrphans -StepTimeoutSec 600 -SkipBookmarkInsert`
- wygenerowanie lekkiego canvasu Word (z bookmarkami z mapy):
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...\\205f_word_create_embed_canvas.ps1`
- pełny przebieg z podaniem innego configu (pod nowe repo):
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...\\205f_run_pipeline.ps1 -ConfigPath <sciezka_do_config.json>`

## Export do osobnego repo (whitelist)

Do publikacji tylko potrzebnych plików (bez śmieci artefaktowych) używamy:
- manifest: `config/205_export_manifest_v01.txt`
- skrypt: `tools/205f_export_research_pack.py`
- domyślne spłaszczenie ścieżek w paczce: `...` -> `research-venom/...`
- bezpiecznik sekretów: eksport automatycznie blokuje pliki typu `.env*`, `secrets/`, `*secret*`, `*token*`, `*credential*`, `*.pem/*.key/...`

Przykłady:
- podgląd (bez kopiowania):
  - `python3 tools/205f_export_research_pack.py --dry-run`
- export paczki:
  - `python3 tools/205f_export_research_pack.py`
- export bez spłaszczania (zachowaj pełną ścieżkę źródła):
  - `python3 tools/205f_export_research_pack.py --strip-prefix \"\"`
- export do konkretnego katalogu:
  - `python3 tools/205f_export_research_pack.py --out-dir /home/ubuntu/exports/research-venom-pack_manual`

### Wariant: tylko review skryptów

Jeśli celem jest recenzja jakości skryptów (a nie pełna transparentność danych), użyj wąskiego manifestu:
- `config/205_export_manifest_scripts_review_v01.txt`
- ten wariant obejmuje też:
  - `PR_205_REVIEW.md` (zakres recenzji dla reviewerów),
  - `.github/workflows/scripts-review-ci.yml` (lekki CI syntax/parse + dry-run export),
  - `.github/copilot-instructions.md` (zakres dla GitHub Copilot),
  - `.gitignore` dla repo `research-venom`.

Przykład:
- `python3 tools/205f_export_research_pack.py --manifest /home/ubuntu/research-venom/config/205_export_manifest_scripts_review_v01.txt`
