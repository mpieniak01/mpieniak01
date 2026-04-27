# AGENTS - 205 Artifacts (subproject rules)

Cel: to repo (`research-venom`) jest podprojektem badawczym serii 205.
Nie jest to kod produkcyjny platformy Venom.

## 1. Zakres odpowiedzialności

1. `205/205B/205C/205D/205E/205F` - zakresy PR, analizy, dane wejściowe i produkty badań.
2. `tools/` - skrypty pomocnicze tylko dla serii 205.
3. `demo/` - eksperymenty techniczne (Excel/Word).
4. `produkty/` - katalog produktów głównych i pośrednich pracy dyplomowej.

## 2. Zasady separacji od głównego projektu

1. Nie dodajemy skryptów badawczych do `scripts/ops` (to strefa produkcyjna Venom).
2. Skrypty 205 utrzymujemy wyłącznie w `tools/`.
3. Artefakty badań zapisujemy wyłącznie w `<seria>/...`.

## 3. Środowisko uruchomieniowe

1. Bazowe środowisko: WSL Ubuntu (`/home/ubuntu/research-venom`).
2. Dopuszczone wywołania Windows z WSL (gdy potrzebne):
   - `powershell.exe`
   - COM Excel (`Excel.Application`) dla `.xlsx` i wykresów editable
   - COM Word (`Word.Application`) dla `.docx` i osadzania wykresów
3. Potwierdzone w praktyce:
   - odczyt i zapis dokumentów Word przez COM działa poprawnie z WSL,
   - możliwa edycja końca dokumentu (dopisywanie treści na ostatniej stronie),
   - możliwa praca na większych plikach DOCX (test wykonany na dokumencie ~2 MB, 43 strony).
4. Sekrety:
   - `.env.dev` (np. `GITHUB_TOKEN`, `SONAR_TOKEN`)
   - nie kopiujemy sekretów do artefaktów

## 4. Reguły danych i produktów

1. Preferowane formaty źródłowe: `CSV` + `JSON`.
2. Produkty raportowe: `MD` + `JSON` + `XLSX` (jeśli wizualizacja).
3. Wykresy domyślnie tworzymy jako natywne obiekty Excela (edytowalne), nie tylko statyczne obrazy.
4. Jeśli eksport PNG jest potrzebny, traktujemy go jako produkt pomocniczy.
5. Produkt główny: dokument Word pracy (`produkty/word/final/*.docx`).
6. Produkt pośredni: skoroszyt Excel workspace (`produkty/excel/workspace/*.xlsx`) z kartami:
   - źródła czyste,
   - źródła przetworzone,
   - wykresy robocze.
7. Dla wykresów do publikacji obowiązkowe są:
   - stały `chart_id` (nazwa obiektu wykresu w Excel),
   - mapa osadzania `Excel chart_id -> Word bookmark` w `205F/inputs/`.

## 5. Konwencje ścieżek

1. PR scope: `<seria>/<seria>_pr_studies_*_dev.md`
2. Analizy: `<seria>/analysis/`
3. Dane wejściowe: `<seria>/inputs/`
4. Serie czasowe: `<seria>/timeseries/`
5. Produkty wizualne (205F): `205F/products/`
6. Skrypty serii 205: `tools/205<ETAP>_<obszar>_<cel>.py`

## 6. Uruchamianie skryptów

Uruchamiamy z root repo (`/home/ubuntu/research-venom`):

```bash
python3 tools/sonar_market_benchmark.py --help
python3 tools/205C_github_market_benchmark_q1.py --help
python3 tools/205D_github_pr_flow_q1.py --help
python3 tools/205E_github_closed_pr_analysis.py --help
```

## 7. Stabilność i powtarzalność

1. Każde zadanie ma sekcję `Produkty (co przedstawiają)`.
2. Po zmianie struktury katalogów aktualizujemy linki w PR i analizach.
3. Unikamy ręcznego mieszania starych i nowych ścieżek (`docs_dev/_to_do/205...` vs `...`).
4. Wersjonowanie plików jest obowiązkowe (katalog poza git):
   - nowe przetworzenie zapisujemy jako nowy plik, bez nadpisywania,
   - sufiks wersji: `_vNN` (np. `_v01`, `_v02`, `_v03`),
   - finalny eksport publikacyjny może mieć dodatkowo sufiks `_FINAL`.

## 8. Reguły demo

1. `demo/` zawiera testy techniczne i proof-of-concept (Excel/Word).
2. Pliki tymczasowe (`~$*.xlsx`, `/tmp/*.ps1`) mogą powstawać podczas automatyzacji COM.
3. Do archiwizacji zostawiamy tylko artefakty końcowe, nie śmieci wykonawcze.
4. Test Word COM uznany za zaliczony: dokument otwiera się poprawnie pod Windows po edycji z WSL.
5. `demo/` nie jest katalogiem produktu końcowego - służy wyłącznie do testów metod i narzędzi.
