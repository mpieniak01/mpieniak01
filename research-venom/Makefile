PYTHON ?= .venv/bin/python
POWERSHELL ?= $(shell command -v pwsh 2>/dev/null || command -v powershell.exe 2>/dev/null || echo pwsh)
CONFIG_V3 ?= config/process_pipeline_v03.json
CONFIG_V4 ?= config/process_pipeline_v04.json
CONFIG_V4_TEST ?= config/process_pipeline_v04_test.json
CONFIG_V4_LOCAL_REAL ?= config/process_pipeline_v04_local_real.json
CONFIRM_API ?= 0
GITLEAKS_SCOPE ?= repo
GITLEAKS_PATHS ?= tools config docs tests artifacts/inputs .github README.md Makefile requirements-ci.txt

.PHONY: help \
        test test-contracts test-contracts-ci test-contracts-local-real verify-input-mode-contract-ci verify-input-mode-contract-local-real \
        test-data-local test-static test-powershell-parse test-security \
        fetch-sonar fetch-github-market fetch-pr-flow fetch-pr-comments fetch-all require-api-confirm \
        fetch-sonar-v3 fetch-github-market-v3 fetch-pr-flow-v3 fetch-pr-comments-v3 fetch-all-v3 \
        process-sources process-summary process process-v3 process-v4 audit-template audit-template-v3 audit-template-v4 \
        product-excel-only product-excel-v3 product-excel-v4 product-all product-all-v3 product-all-v4

help:
	@echo "Tests:"
	@echo "  make test-contracts        Fast logic-contract tests, CI-safe"
	@echo "  make test-contracts-ci     CI contract: tests on sample inputs"
	@echo "  make test-contracts-local-real  Local contract: private real inputs from _external/not_tracked"
	@echo "  make test-data-local       Local data quality tests over private artifacts"
	@echo "  make test-static           Python/help/static checks"
	@echo "  make test-powershell-parse Parse PowerShell scripts without Office COM"
	@echo "  make test-security         Local OSS security gate (gitleaks + pip-audit + bandit)"
	@echo "    - GITLEAKS_SCOPE=repo    Scan git history (default, mirrors CI)"
	@echo "    - GITLEAKS_SCOPE=paths   Scan only selected paths from GITLEAKS_PATHS"
	@echo "Data fetch, explicit API:"
	@echo "  CONFIRM_API=1 make fetch-all"
	@echo "  CONFIRM_API=1 make fetch-github-market"
	@echo "Local processing, no API:"
	@echo "  make process               S01+S02 from existing artifacts"
	@echo "  make audit-template        XLSX XML audit without Office COM"
	@echo "Products, Office COM:"
	@echo "  make product-excel-only    Build Excel workbook and charts, skip Word"
	@echo "  make product-all           Full product pipeline including Word"

require-api-confirm:
	@test "$(CONFIRM_API)" = "1" || (echo "API fetch requires CONFIRM_API=1" && exit 2)

test: test-contracts test-static

test-contracts:
	$(PYTHON) -m pytest -q -m "not windows_office and not network and not data_quality"

verify-input-mode-contract-ci:
	$(PYTHON) tools/verify_input_mode_contract.py --mode ci

verify-input-mode-contract-local-real:
	$(PYTHON) tools/verify_input_mode_contract.py --mode local-real

test-contracts-ci: verify-input-mode-contract-ci test-contracts test-static test-powershell-parse

test-contracts-local-real: verify-input-mode-contract-local-real test-contracts

test-data-local:
	RUN_DATA_QUALITY_TESTS=1 $(PYTHON) -m pytest -q -m data_quality

test-static:
	$(PYTHON) -m py_compile tools/*.py
	$(PYTHON) tools/sonar_market_benchmark.py --help >/dev/null
	$(PYTHON) tools/github_market_benchmark.py --help >/dev/null
	$(PYTHON) tools/github_pr_flow.py --help >/dev/null
	$(PYTHON) tools/github_closed_pr_analysis.py --help >/dev/null
	$(PYTHON) tools/prepare_sources.py --help >/dev/null
	$(PYTHON) tools/build_summary_tables.py --help >/dev/null
	$(PYTHON) tools/template_chart_audit.py --help >/dev/null
	$(PYTHON) tools/export_research_pack.py --help >/dev/null
	$(PYTHON) tools/report_alias_coverage.py --help >/dev/null
	$(PYTHON) tools/verify_input_mode_contract.py --help >/dev/null

test-powershell-parse:
	$(POWERSHELL) -NoProfile -Command '$$errors = @(); Get-ChildItem -Path tools -Filter *.ps1 | ForEach-Object { $$tokens = $$null; [System.Management.Automation.Language.Parser]::ParseFile($$_.FullName, [ref]$$tokens, [ref]$$errors) | Out-Null }; if ($$errors.Count -gt 0) { $$errors | ForEach-Object { Write-Host $$_.Message }; throw "PowerShell parse errors detected." }'

test-security:
	@if ! command -v gitleaks >/dev/null 2>&1; then echo "Missing gitleaks in PATH"; exit 2; fi
	@if [ "$(GITLEAKS_SCOPE)" = "repo" ]; then \
		echo "gitleaks scope=repo (git history)"; \
		gitleaks git --redact --verbose; \
	elif [ "$(GITLEAKS_SCOPE)" = "paths" ]; then \
		echo "gitleaks scope=paths ($(GITLEAKS_PATHS))"; \
		for p in $(GITLEAKS_PATHS); do \
			if [ -e "$$p" ]; then \
				echo "scan path: $$p"; \
				gitleaks detect --source "$$p" --no-git --redact --verbose; \
			fi; \
		done; \
	else \
		echo "Unsupported GITLEAKS_SCOPE=$(GITLEAKS_SCOPE). Use repo or paths."; \
		exit 2; \
	fi
	$(PYTHON) -m pip_audit --progress-spinner off -r requirements-ci.txt
	@if command -v bandit >/dev/null 2>&1; then bandit -q -r tools -ll; else echo "Missing bandit in PATH"; exit 2; fi

fetch-sonar: require-api-confirm
	$(PYTHON) tools/sonar_market_benchmark.py --config $(CONFIG_V4) --dataset-id sonar_market --mode timeseries

fetch-github-market: require-api-confirm
	$(PYTHON) tools/github_market_benchmark.py --config $(CONFIG_V4) --dataset-id github_market --mode analyze --max-commits-per-repo 0

fetch-pr-flow: require-api-confirm
	$(PYTHON) tools/github_pr_flow.py --config $(CONFIG_V4) --dataset-id github_pr_flow

fetch-pr-comments: require-api-confirm
	$(PYTHON) tools/github_closed_pr_analysis.py --config $(CONFIG_V4) --dataset-id github_pr_comments

fetch-all: require-api-confirm fetch-sonar fetch-github-market fetch-pr-flow fetch-pr-comments

process-sources:
	$(PYTHON) tools/prepare_sources.py --config $(CONFIG_V4) --dataset-id visualization_sources_pack

process-summary:
	$(PYTHON) tools/build_summary_tables.py --config $(CONFIG_V4) --dataset-id visualization_summary_tables

process: process-sources process-summary

audit-template:
	$(PYTHON) tools/template_chart_audit.py --template artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx --chart-spec artifacts/inputs/visualization/chart_spec_v04.json --out-md artifacts/products_light/visualization/template_chart_audit_v04.md --out-json artifacts/products_light/visualization/template_chart_audit_v04.json

product-excel-only:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4) -SkipWord

fetch-sonar-v3: require-api-confirm
	$(PYTHON) tools/sonar_market_benchmark.py --config $(CONFIG_V3) --dataset-id sonar_market --mode timeseries

fetch-github-market-v3: require-api-confirm
	$(PYTHON) tools/github_market_benchmark.py --config $(CONFIG_V3) --dataset-id github_market --mode analyze --max-commits-per-repo 0

fetch-pr-flow-v3: require-api-confirm
	$(PYTHON) tools/github_pr_flow.py --config $(CONFIG_V3) --dataset-id github_pr_flow

fetch-pr-comments-v3: require-api-confirm
	$(PYTHON) tools/github_closed_pr_analysis.py --config $(CONFIG_V3) --dataset-id github_pr_comments

fetch-all-v3: require-api-confirm fetch-sonar-v3 fetch-github-market-v3 fetch-pr-flow-v3 fetch-pr-comments-v3

process-v3:
	$(PYTHON) tools/prepare_sources.py --config $(CONFIG_V3) --dataset-id visualization_sources_pack
	$(PYTHON) tools/build_summary_tables.py --config $(CONFIG_V3) --dataset-id visualization_summary_tables

process-v4:
	$(PYTHON) tools/prepare_sources.py --config $(CONFIG_V4) --dataset-id visualization_sources_pack
	$(PYTHON) tools/build_summary_tables.py --config $(CONFIG_V4) --dataset-id visualization_summary_tables

audit-template-v3:
	$(PYTHON) tools/template_chart_audit.py --template artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx --chart-spec artifacts/inputs/visualization/chart_spec_v03.json --out-md artifacts/products_light/visualization/template_chart_audit_v03.md --out-json artifacts/products_light/visualization/template_chart_audit_v03.json

audit-template-v4:
	$(PYTHON) tools/template_chart_audit.py --template artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx --chart-spec artifacts/inputs/visualization/chart_spec_v04.json --out-md artifacts/products_light/visualization/template_chart_audit_v04.md --out-json artifacts/products_light/visualization/template_chart_audit_v04.json

product-excel-v3:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V3) -SkipWord

product-excel-v4:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4) -SkipWord

product-all:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4)

product-all-v3:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V3)

product-all-v4:
	powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/run_pipeline.ps1 -ConfigPath $(CONFIG_V4)
