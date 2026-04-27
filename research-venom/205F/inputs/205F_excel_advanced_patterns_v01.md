# 205F Excel Advanced Patterns v01

Cel: ujednolicić techniki dla wykresów opisowych (Typ B), aby nie tracić kontroli przy osadzaniu do Word.

## 1. Zakres

Dotyczy wykresów, które poza serią główną zawierają warstwę narracyjną:
- podświetlenie faz,
- punkty przełomowe,
- progi referencyjne,
- adnotacje i opisy kontekstowe.

## 2. Wzorce techniczne

1. `background_series`
   - serie pomocnicze do kolorowania tła (np. fazy Q1).
   - zwykle realizowane przez kolumny/obszary o wysokiej przezroczystości.

2. `label_series`
   - osobna seria z punktami kontrolnymi i etykietami.
   - etykieta może być przesunięta poza obszar głównego wykresu.

3. `reference_lines`
   - linie pionowe: daty graniczne (start/end fazy, release).
   - linie poziome: progi KPI (np. coverage target, debt threshold).

4. `annotation_shapes`
   - obiekty Excel: textbox, strzałka, kształt.
   - używane tylko do objaśnień, nie jako nośnik danych liczbowych.

## 3. Minimalna specyfikacja dla wykresu Typu B

Każdy wykres Typu B musi mieć w specyfikacji:
1. `chart_id`
2. `source_sheet`
3. `x_series`
4. `y_series[]`
5. `background_series[]` (jeśli użyto)
6. `label_series[]` (jeśli użyto)
7. `reference_lines[]` (jeśli użyto)
8. `annotation_shapes[]` (jeśli użyto)
9. mapowanie `word_bookmark`

## 4. Reguły kontroli

1. Bez `chart_id` wykres nie trafia do Word.
2. Bez wpisu w `205F_word_embed_map_vNN` wykres nie trafia do Word.
3. Zmiana warstwy narracyjnej = nowa wersja pliku `_vNN`.
4. Nie nadpisujemy poprzednich wersji produktów.

## 5. Relacja do innych artefaktów

1. `205F_chart_spec_v01.json` - źródło definicji wykresów.
2. `205F_word_embed_map_v01.csv` - mapowanie Excel -> Word.
3. `205F_excel_sheet_layout_v01.csv` - układ zakładek w skoroszycie.
