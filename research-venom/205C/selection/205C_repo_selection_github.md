# 205C_repo_selection_github

Data generacji: `2026-04-22T18:46:58Z`

## Parametry

- `Q1`: `2026-01-01` -> `2026-03-31`
- `language`: `Python `
- `size_min_kb`: `50000`
- `size_max_kb`: `null` (brak górnego limitu)
- `project_limit`: `10`
- `min_commits_q1`: `1`

## Wybrane repo

| Repo | Commits Q1 | Size (KB) | Stars | Language | Bio projektu |
|---|---:|---:|---:|---|---|
| `neuropsychology/NeuroKit` | 105 | 4674896 | 2201 | Python | NeuroKit2: The Python Toolbox for Neurophysiological Signal Processing |
| `allenai/olmocr` | 94 | 357497 | 17160 | Python | Toolkit for linearizing PDFs for LLM datasets/training |
| `virt-manager/virt-manager` | 57 | 99926 | 3116 | Python | Desktop tool for managing virtual machines via libvirt |
| `hiddify/Hiddify-Manager` | 65 | 76732 | 8711 | Python | Multi-user anti-filtering panel, with an effortless installation and supporting more than 20 protocols to circumvent filtering plus the telegram proxy. |
| `JefferyHcool/BiliNote` | 62 | 58932 | 5743 | Python | AI 视频笔记生成工具 让 AI 为你的视频做笔记 |
| `originalankur/maptoposter` | 51 | 319926 | 13004 | Python | Transform your favorite cities into beautiful, minimalist designs. MapToPoster lets you create and export visually striking map posters with code. |
| `FreedomIntelligence/OpenClaw-Medical-Skills` | 46 | 77628 | 2145 | Python | The largest open-source medical AI skills library for OpenClaw🦞. |
| `xlenore/ps2-covers` | 45 | 8549266 | 4129 | Python | PS2 Covers Collection |
| `omkarcloud/botasaurus` | 43 | 91623 | 4375 | Python | The All in One Framework to Build Undefeatable Scrapers |
| `khoj-ai/khoj` | 39 | 117335 | 34194 | Python | Your AI second brain. Self-hostable. Get answers from the web or your docs. Build custom agents, schedule automations, do deep research. Turn any online or local LLM into your personal, autonomous AI (gpt, claude, gemini, llama, qwen, mistral). Get started - free. |

## Uwaga metodologiczna

- `project_limit=10` dotyczy tylko próby rynkowej (repo z wyszukiwarki).
- Dodatkowo do analiz porównawczych dokładany jest `baseline_repo`: `mpieniak01/Venom`.
- Dlatego artefakty timeseries/analysis mogą zawierać łącznie 11 repozytoriów.
- Pliki wejściowe:
  - próba rynkowa (10 repo): `205C/inputs/205C_repo_keys_selected.txt`
  - baseline Venom: `205C/inputs/205C_repo_key_baseline.txt`
