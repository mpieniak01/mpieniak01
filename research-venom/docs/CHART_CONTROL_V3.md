# Chart Control v3

`v03` jest już dopasowane do szablonu `artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx`. To nie jest tylko abstrakcyjny profil sterowania, ale kontrakt dla 17 arkuszy i 21 wykresów w workbooku `workbook_v03.xlsx`.

## Zakres

W `v03` kontrakt obejmuje:

- role serii,
- typ serii w obrębie jednego wykresu,
- grupę osi (`primary` / `secondary`),
- tryb prezentacji wykresu,
- kolejność serii w chartach mieszanych,
- reguły traktowania serii tła faz jako serii oczekiwanych, ale częściowo pustych poza swoim zakresem dat.

## Pliki

- `artifacts/inputs/visualization/chart_control_profile_v03.json`
- `artifacts/inputs/visualization/chart_spec_v03.json`
- `artifacts/inputs/visualization/workbook_layout_v03.json`
- `artifacts/inputs/visualization/chart_style_profile_v03.json`
- `config/process_pipeline_v03.json`

## Mapowanie szablonu

| Arkusz | Typ wykresu | Charakter |
|---|---|---|
| `W31_Commity`, `W32_LOC`, `W36_Dlug_Projekty` | `bar_horizontal` | porównanie projektów |
| `W37_Trajektoria_Dlug`, `W35_Trajektoria_Q1`, `W42_FazaII`, `W43_FazaII`, `W33_Dzienny_Przeplyw`, `WP5_Venom_PR_Daily`, `WP6_Venom_Lead_Time` | `combo` | tło aktywnych faz + sygnał właściwy |
| `WP1_PR_Wolumen` | `bar_stacked` | wolumen PR w rozbiciu na status |
| `WP2_Lead_Time`, `WP3_Merge_Rate`, `WP4_Backlog` | `bar_horizontal` | benchmark procesu PR |

## Kolejność serii

W chartach `combo` serie tła faz są zawsze pierwsze w `series_plan` i `y_series`.
Następnie pojawiają się serie właściwe, np. `issues`, `coverage`, `lead time` albo `PR volume`.

To jest wymagane, bo:

- tło faz ma być warstwą narracyjną, nie głównym sygnałem,
- Excel inaczej traktuje mieszane chart types, jeśli kolejność serii jest odwrócona,
- walidacja odróżnia puste tło faz od faktycznie brakującej metryki.

## Model sterowania

Główne tryby prezentacji:

| Tryb | Znaczenie |
|---|---|
| `trend` | seria czasowa i sygnał główny |
| `comparison` | porównanie kategorii / projektów |
| `combo` | wykres mieszany z tłem faz i sygnałem |
| `mix` | tryb roboczy dla różnych skal w jednym wykresie |

## Zasady serii

- `primary` - główna seria sygnału na osi podstawowej.
- `secondary` - seria pomocnicza na osi sekundarnej.
- `reference` - benchmark lub punkt odniesienia.
- `label` - seria opisowa.
- `phase` - seria tła faz, dopuszczalnie pusta poza zakresem fazy.

## Kontrakt faz

Globalny profil faz jest zapisany w `chart_control_profile_v03.json` i obowiązuje wszystkie wykresy combo:

- `phase_i`: `2026-01-01` -> `2026-02-05`
- `phase_ii`: `2026-02-06` -> `2026-03-06`
- `phase_iii`: `2026-03-07` -> `2026-03-31`

Warstwa tła faz:

- ma wartość `100`,
- jest prowadzona na osi `secondary`,
- ma jawny kontrakt osi `0..100`,
- nie może autoskalowac osi do `120` lub wyżej,
- nie może wpływać na zakres osi głównej.
- jest renderowana jako lekkie tło z przezroczystością, a nie ciężki blok zasłaniający metrykę.
- generator Excela po dodaniu wszystkich serii ponownie wymusza `AxisGroup=secondary` i `chart_type=column` dla serii `phase_*`, ponieważ Excel COM przy chartach mieszanych potrafi samodzielnie przypiąć pierwszą serię kolumnową do osi głównej.

Chart nie musi pokazywać wszystkich faz. `active_phase_fields` w `chart_spec_v03.json` wskazuje, które fazy są renderowane:

- `active_data_only` pokazuje tylko fazy, w których istnieje realna metryka właściwa,
- `declared_phase_only` pokazuje tylko fazę opisaną przez chart, np. `W42_FazaII`,
- `full_project` jest dopuszczalny tylko wtedy, gdy pełny kontekst Q1 jest jawnie potrzebny.

Zakres osi dat jest osobną konfiguracją. Jeśli chart zaczyna się od aktywnej fazy późniejszej niż `phase_i`, musi mieć:

- `x_axis_scope_mode = active_phase_range`,
- `x_axis_start` jako początek pierwszej aktywnej fazy,
- `x_axis_end` jako koniec ostatniej aktywnej fazy.

Przykład: `W37_Trajektoria_Dlug` ma aktywne `phase_ii` i `phase_iii`, więc oś X zaczyna się od `2026-02-06`. Nie pokazujemy pustej części styczniowej, bo nie ma tam danych metryki właściwej.

## Kontrakt Typu Metryki

Typ serii wynika z semantyki danych, a nie tylko z układu szablonu:

- `continuous_state` może być linią, jeśli wartości opisują stan lub trajektorię,
- `daily_event` powinien być kolumną, bo pokazuje przepływ dzienny,
- `sparse_event` powinien być kolumną, bo połączenie punktów linią sugeruje fałszywy trend,
- `project_comparison` używa układu poziomego albo stacked zgodnie z typem porównania.

Przykład: `WP6_Venom_Lead_Time` używa kolumn dla lead time, bo wartości wynikają z zamkniętych/mergowanych PR, a nie z ciągłego stanu procesu.

## Kontrakt osi dat

Wykresy czasowe używają jednego globalnego profilu osi dat:

- oś jest traktowana jako globalna oś kategorii,
- etykiety pokazują tylko `mm-dd`,
- rytm etykiet to tydzień (`7` dni),
- rok `2026` nie jest powtarzany na każdym ticku,
- kontrakt jest wspólny dla wszystkich chartów z `x_series = date`.

## Kontrakt Venom Anchor

Charty porownawcze `WP1`-`WP4` używają wspólnego kontraktu `Venom anchor`:

- `mpieniak01/Venom` jest zawsze obecny w porównaniu,
- reszta projektów jest dobierana jako deterministyczna najbliższa grupa wokół Venom,
- kolejność w tabeli zaczyna się od Venom, żeby punkt odniesienia był natychmiast widoczny,
- kontrakt dotyczy źródła danych i nie wymaga ręcznego przesuwania serii w Excelu.

## Walidacja

- `phase_*` może być całkowicie puste poza swoim zakresem dat i nadal jest poprawne.
- `series_all_null_background` jest ostrzeżeniem, nie błędem.
- `series_all_null_optional` dotyczy serii opcjonalnych, które są częścią kontraktu szablonu, ale nie zawsze są dostępne w danych wejściowych.
- Seria `phase_*` nie skaluje osi głównej. Jest normalizowana do `100`, prowadzona na osi pomocniczej i renderowana jako `column`, dzięki czemu wypełnia wysokość wykresu bez wpływu na zakres metryki głównej.
- Walidator sprawdza realny `AxisGroup` każdej serii fazy w gotowym workbooku; przypadek, w którym tylko `Faza I` ląduje na osi głównej, jest błędem stylu, nawet jeśli JSON specyfikacji deklaruje `secondary`.
- Walidator sprawdza też `metric_semantics`: serie `daily_event` i `sparse_event` nie mogą być renderowane jako `line`.
- Walidator porównuje `active_phase_fields` z realnie renderowanymi seriami faz, żeby chart jednofazowy nie pokazywał pustych faz.
- Testy kontraktowe sprawdzają, czy `x_axis_start` i `x_axis_end` są zgodne z zakresem aktywnych faz.
- To dotyczy także wykresów procentowych, np. `W43_FazaII`; skala `100` jest kontraktem tła, a nie wynikiem z danych metryki.
- Opisy `sheet_description` i `table_description` są source-first: najpierw wskazują źródło domenowe (`GitHub API`, `SonarCloud API`, `PR flow`), potem `src_*` albo `wrk_*`, dopiero potem skrót biznesowy.
- Dla chartów z projektami kontrakt jest jawny:
  - `input_project_count` rozróżnia pełny zbiór wejściowy od zredukowanego podzbioru renderowanego,
  - `rendered_project_keys` przechowuje pełną listę kluczy projektów pokazywanych na chartcie,
  - nazwy projektów nie mogą być zwijane do `inne` ani skracane do ukrytej listy.
- Oś dat jest formatowana globalnie, więc workbook pokazuje `mm-dd` bez powtarzania roku `2026` na każdym wykresie.
- Charty `WP1`-`WP4` pokazują `Venom anchor` jako pierwszy punkt odniesienia, a peer group jest zacieśniana do deterministycznie wybranych najbliższych projektów.

## Audyt skali

Aktualny audyt zakresów i osi znajduje się w:

- `artifacts/products_light/visualization/chart_scale_audit_v03.md`

W praktyce oznacza to:

- wykresy `combo` z fazami mają stałą warstwę tła `100` na osi `secondary`,
- oś główna bierze zakres z metryki właściwej,
- przykładowo `W37_Trajektoria_Dlug` skaluje się do wartości `technical_debt_days` i `issues`, a nie do wysokości tła faz.

## Praktyka

`chart_spec_v03.json` nadal może zawierać klasyczne `x_series/y_series`, ale zalecaną formą jest `series_plan`.
To pozwala zachować zgodność ze szablonem bez przepisywania generatorów danych przy każdej zmianie układu wykresu.
