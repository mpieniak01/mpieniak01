# PR_205 Review Scope

Cel: ten artefakt definiuje zakres recenzji zewnętrznej dla pakietu `research-venom`.

## Co recenzujemy

1. Jakość skryptów w `tools/`:
   - czytelność,
   - spójność interfejsów CLI,
   - obsługa błędów i logowanie,
   - bezpieczeństwo operacyjne (brak destrukcyjnych skutków ubocznych),
   - przenaszalność konfiguracji.

2. Konfigurację i politykę publikacji:
   - `config/205f_pipeline_config_v01.json`,
   - manifesty whitelist eksportu (`config/205_export_manifest*.txt`).

3. Minimalne reguły automatycznej kontroli:
   - `.github/workflows/scripts-review-ci.yml`,
   - `.github/copilot-instructions.md`,
   - `.gitignore`.

## Czego NIE recenzujemy w tym PR

1. Wyników merytorycznych badań (wnioski naukowe, interpretacje trendów).
2. Kompletności historycznych danych wejściowych i surowych dumpów API.
3. Jakości końcowej narracji pracy dyplomowej.

## Kryteria akceptacji recenzji

1. Skrypty przechodzą podstawowy check techniczny (syntax/parse/dry-run export).
2. Konfiguracja jest odseparowana od kodu i możliwa do przeniesienia do innego repo.
3. Publikacja odbywa się wyłącznie whitelistą, bez przypadkowego wynoszenia artefaktów lokalnych.
4. Zakres repo jest jednoznaczny: projekt badawczy, nie kod produkcyjny Venom.

## Pakiet docelowy

Publikacja do repo wizytówki jako podkatalog:
- `research-venom/`

Struktura recenzencka:
- `README.md`
- `PR_205_REVIEW.md`
- `tools/`
- `config/`
- `.github/`
- `.gitignore`
