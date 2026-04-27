# 205B - Typowanie Repo z Explore (LOC >= 50k, język dowolny)

## Podsumowanie

| Metryka | Wartość |
|---|---:|
| Cel (liczba repo) | 10 |
| Znalezione repo spełniające warunki | 9 |
| Przeskanowane repo | 468 |
| Minimalny LOC | 50000 |

## Kryteria

1. `LOC >= 50 000`
2. Komplet metryk: `Issues`, `Technical Debt (days)`, `Lines of Code`, `Line Coverage (%)`, `Unit Tests`
3. Źródło listy: SonarCloud Explore przez API (`/api/components/search_projects`, sortowanie `analysisDate desc`)

## Wytypowane Repo (spełniają warunki)

| # | Project Key | LOC | Issues | Debt (days) | Coverage (%) | Unit Tests |
|---:|---|---:|---:|---:|---:|---:|
| 1 | `org.opengrok:opengrok-top` | 64444 | 1053 | 17.82 | 71.40 | 1524 |
| 2 | `indigo-iam_iam` | 55976 | 835 | 9.09 | 86.10 | 2336 |
| 3 | `Maps-Messaging_mapsmessaging_server` | 107071 | 1000 | 18.34 | 52.40 | 226 |
| 4 | `googleapis_google-cloud-java_generator` | 381179 | 13087 | 161.60 | 3.60 | 3066 |
| 5 | `aws_aws-sdk-java-v2` | 252507 | 4039 | 55.53 | 72.10 | 14028 |
| 6 | `geoserver_geoserver-cloud` | 52663 | 1 | 0.00 | 65.70 | 1915 |
| 7 | `element-web` | 476520 | 5632 | 47.75 | 70.60 | 606 |
| 8 | `mediawiki-core` | 510795 | 3886 | 211.35 | 13.70 | 18060 |
| 9 | `bcgov-sonarcloud_mds_core-web` | 70321 | 811 | 11.41 | 62.00 | 904 |

## Status

Brakuje jeszcze `1` repo do domknięcia pełnej próby `10`.
