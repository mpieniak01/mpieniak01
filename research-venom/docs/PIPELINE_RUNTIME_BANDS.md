# Pipeline Runtime Bands

Ten dokument zbiera empiryczne zakresy czasow krokow procesu z logow w `artifacts/log/`.
Cel jest praktyczny: pokazac skale, a nie precyzyjna wartosc pojedynczego uruchomienia.

## Srodowisko referencyjne

- OS: Ubuntu 24.04.4 LTS na WSL2
- Kernel: `6.6.87.2-microsoft-standard-WSL2`
- CPU: Intel Core i5-14400F
- CPU logiczne: 8
- RAM: 29 GiB
- Swap: 16 GiB

## Zrodlo pomiarow

- `artifacts/log/pipeline_run_v03_20260429T055333Z_9ab459dd.log`
- `artifacts/log/pipeline_run_v03_20260429T054853Z_ee46ed3d.log`
- `artifacts/log/pipeline_run_v03_20260429T054514Z_715d9f3c.log`
- `artifacts/log/pipeline_run_v03_20260428T160755Z_e8fbf544.log`

## Zakresy krokow

| Krok | Opis skrótowy | Liczba obserwacji | Zakres [s] | Mediana [s] | Komentarz |
|---|---|---:|---:|---:|---|
| S00 | hygiene preflight/postflight | 4 | 0.47-0.66 | 0.57 | praktycznie stałe |
| S01 | przygotowanie zrodel | 4 | 0.38-0.41 | 0.40 | praktycznie stałe |
| S02 | summary tables | 4 | 0.32-0.35 | 0.34 | praktycznie stałe |
| S03 | budowa workbooka Excel | 4 | 132.61-151.76 | 137.64 | najciezszy etap |
| S04 | dodawanie wykresow | 4 | 5.63-7.99 | 6.93 | stabilny |
| S05 | advanced patterns | 4 | 2.48-62.55 | 2.52 | jeden silny outlier |
| S06 | bookmark insertion Word | 1 | 4.82-4.82 | 4.82 | widziany w pelnym przebiegu |
| S07 | embed chartow do Word | 1 | 9.01-9.01 | 9.01 | widziany w pelnym przebiegu |
| S08 | walidacja Excel | 4 | 29.37-32.15 | 30.16 | stabilny |
| S09 | walidacja Word | 1 | 6.32-6.32 | 6.32 | widziany w pelnym przebiegu |
| S10 | hygiene postflight | 4 | 0.47-0.53 | 0.50 | praktycznie stałe |

## Interpretacja

- Krok `S03` jest dominujacy czasowo. To on ustala calkowity czas przebiegu.
- Krok `S08` jest drugi w kolejce, ale jest rzedu dziesiatek sekund, nie minut.
- `S05` ma duza zmiennosc, bo obejmuje automatyzacje Office COM oraz dodatkowe metadane.
- Kroki `S01`, `S02`, `S00` i `S10` sa marginalne czasowo.
- Kroki Word (`S06`, `S07`, `S09`) sa istotne, ale nadal ponizej kosztu `S03`.

## Jak czytac te liczby

To sa zakresy operacyjne dla tej klasy srodowiska, a nie SLA.
Ich celem jest odpowiedz na pytanie:
- czy proces zyje i pracuje w spodziewanej klasie czasowej,
- czy ktorys krok zaczyna odstawiac od normy i moze byc zawieszony,
- czy zmiana konfiguracji lub danych istotnie zmienia profil runtimow.
