# 205B - Status Typowania Repo Referencyjnych (SonarCloud)

Data generacji: `2026-04-22T17:06:15Z`

## Podsumowanie

| Metryka | Wartość |
|---|---:|
| Sprawdzone repo | 20 |
| Repo istniejące w SonarCloud (z odpowiedzią endpointu) | 3 |
| Repo z kompletem 5 metryk | 0 |
| Repo w zakresie LOC 80k-160k | 0 |
| Repo spełniające wszystkie kryteria | 0 |

## Kryteria

1. `Lines of Code` (`ncloc`) w zakresie `80 000 - 160 000`.
2. Komplet metryk: `Issues`, `Technical Debt (days)`, `Lines of Code`, `Line Coverage (%)`, `Unit Tests`.

## Tabela Oceny Repo

| Repo Key | Istnieje w Sonar | LOC | LOC OK | Issues | Debt (days) | Coverage (%) | Unit Tests | 5 metryk OK | Finalnie OK | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `pandas-dev_pandas` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `numpy_numpy` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `scikit-learn_scikit-learn` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `psf_requests` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `pallets_flask` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `django_django` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `pytest-dev_pytest` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `pydantic_pydantic` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `tiangolo_fastapi` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `celery_celery` | TAK | - | NIE | - | - | - | - | NIE | NIE | NO_DATA |
| `scrapy_scrapy` | TAK | - | NIE | - | - | - | - | NIE | NIE | NO_DATA |
| `encode_httpx` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `apache_airflow` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `ansible_ansible` | TAK | 168232 | NIE | 0 | 0.00 | - | - | NIE | NIE | PARTIAL |
| `python-poetry_poetry` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `huggingface_transformers` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `home-assistant_core` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `encode_starlette` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `pallets_werkzeug` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |
| `keras-team_keras` | NIE | - | NIE | - | - | - | - | NIE | NIE | NOT_FOUND |

## Wniosek Operacyjny

1. Na obecnej próbce nie ma jeszcze żadnego repo spełniającego pełny zestaw warunków.
2. Kolejny krok: rozszerzyć listę kandydatów o projekty, które mają aktywne publiczne dashboardy SonarCloud i dopiero wtedy zamykać próbę 10 repo.
