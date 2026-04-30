# Execution Environment

## Python

Jedyna aktywacja srodowiska:

```bash
source .venv/bin/activate
```

Nie uzywamy alternatywnych lokalnych venv.

Pakiet zaleznosci dla CI/test:

```bash
python -m pip install --upgrade pip
python -m pip install -r requirements-ci.txt
```

Tryby list kluczy:
- `*_selected_v01.txt` to listy public sample (bez realnych kluczy).
- - CI i testy kontraktowe korzystaja z `config/process_pipeline_v04_test.json`.
- Realny fetch API korzysta lokalnie z `config/process_pipeline_v04_local_real.json` i prywatnych plikow w `_external/not_tracked/inputs/**`.
- Egzekwowanie kontraktu:
  - `make verify-input-mode-contract-ci`
  - `make verify-input-mode-contract-local-real`

Security audit dla projektu wykonujemy na pliku zaleznosci projektu, nie na calym aktywnym srodowisku:

```bash
python -m pip_audit -r requirements-ci.txt --progress-spinner off
```

## PowerShell

- `pwsh` (PowerShell 7): parse-check i kroki bez Office COM.
- `powershell.exe` (Windows): wymagany dla Office COM.

W WSL kroki COM uruchamiamy przez Windows:

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath config/process_pipeline_v04.json
```

`pwsh` w Linux/WSL nie zastapi COM Word/Excel.

## Makefile jako interfejs pracy

Dla codziennej pracy uzywaj `make help`. Targety sa podzielone na bezpieczne lokalne testy, jawne pobieranie danych z API, lokalne przetwarzanie oraz generowanie produktow Office.

Bezpieczne dla CI i lokalnych zmian kodu:

```bash
make test-contracts
make test-contracts-ci
make test-static
make process
```

Tylko lokalnie i swiadomie:

```bash
make test-contracts-local-real
RUN_DATA_QUALITY_TESTS=1 make test-data-local
CONFIRM_API=1 make fetch-github-market
make product-excel-only
```

Kroki `fetch-*` wymagaja `CONFIRM_API=1`, zeby nie zuzywac limitow API przypadkowo. Kroki `product-*` wymagaja Windows `powershell.exe` i Office COM.
