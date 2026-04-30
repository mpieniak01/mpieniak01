#!/usr/bin/env python3
"""Audit chart contracts embedded in an XLSX template.

The script intentionally reads the XLSX package XML directly so it does not add
runtime dependencies to the pipeline environment.
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import zipfile
from pathlib import Path
from typing import Any

import defusedxml.ElementTree as ET

from path_config import repo_root_from_script

NS = {
    "main": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
    "pkgrel": "http://schemas.openxmlformats.org/package/2006/relationships",
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "c": "http://schemas.openxmlformats.org/drawingml/2006/chart",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit XLSX template charts.")
    parser.add_argument(
        "--template",
        default="artifacts/template/Wykresy_Venom_FORMULY_v6.xlsx",
    )
    parser.add_argument(
        "--chart-spec",
        default="artifacts/inputs/visualization/chart_spec_v04.json",
    )
    parser.add_argument(
        "--out-md",
        default="artifacts/products_light/visualization/template_chart_audit_v04.md",
    )
    parser.add_argument(
        "--out-json",
        default="artifacts/products_light/visualization/template_chart_audit_v04.json",
    )
    return parser.parse_args()


def _read_xml(zf: zipfile.ZipFile, name: str) -> ET.Element:
    return ET.fromstring(zf.read(name))


def _rels_path(part: str) -> str:
    directory = posixpath.dirname(part)
    basename = posixpath.basename(part)
    return posixpath.join(directory, "_rels", basename + ".rels")


def _resolve(base_part: str, target: str) -> str:
    if target.startswith("/"):
        return target.lstrip("/")
    return posixpath.normpath(posixpath.join(posixpath.dirname(base_part), target))


def _relmap(zf: zipfile.ZipFile, part: str) -> dict[str, dict[str, str]]:
    rels = _rels_path(part)
    if rels not in zf.namelist():
        return {}
    root = _read_xml(zf, rels)
    return {
        rel.attrib["Id"]: rel.attrib
        for rel in root.findall(f"{{{NS['pkgrel']}}}Relationship")
    }


def _title_text(node: ET.Element | None) -> str:
    if node is None:
        return ""
    return "".join(t.text or "" for t in node.findall(".//a:t", NS))


def _formula(node: ET.Element | None) -> str:
    if node is None:
        return ""
    f_node = node.find(".//c:f", NS)
    return f_node.text if f_node is not None and f_node.text else ""


def _series_name(ser: ET.Element) -> str:
    tx = ser.find("c:tx", NS)
    if tx is None:
        return ""
    value = tx.find(".//c:v", NS)
    if value is not None and value.text:
        return value.text
    return _formula(tx)


def _chart_node_name(node: ET.Element) -> str:
    match = re.match(r"\{[^}]+\}(.+)", node.tag)
    return match.group(1) if match else node.tag


def _template_charts(template: Path) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    with zipfile.ZipFile(template) as zf:
        workbook = _read_xml(zf, "xl/workbook.xml")
        workbook_rels = _relmap(zf, "xl/workbook.xml")
        for sheet in workbook.findall("main:sheets/main:sheet", NS):
            sheet_name = sheet.attrib["name"]
            rel_id = sheet.attrib[f"{{{NS['r']}}}id"]
            sheet_part = _resolve("xl/workbook.xml", workbook_rels[rel_id]["Target"])
            sheet_root = _read_xml(zf, sheet_part)
            drawing = sheet_root.find("main:drawing", NS)
            if drawing is None:
                continue
            drawing_rel_id = drawing.attrib.get(f"{{{NS['r']}}}id")
            sheet_rels = _relmap(zf, sheet_part)
            if not drawing_rel_id or drawing_rel_id not in sheet_rels:
                continue
            drawing_part = _resolve(sheet_part, sheet_rels[drawing_rel_id]["Target"])
            drawing_root = _read_xml(zf, drawing_part)
            drawing_rels = _relmap(zf, drawing_part)
            for chart_ref in drawing_root.findall(".//c:chart", NS):
                chart_rel_id = chart_ref.attrib.get(f"{{{NS['r']}}}id")
                if not chart_rel_id or chart_rel_id not in drawing_rels:
                    continue
                chart_part = _resolve(drawing_part, drawing_rels[chart_rel_id]["Target"])
                chart_root = _read_xml(zf, chart_part)
                chart_el = chart_root.find("c:chart", NS)
                plot = chart_el.find("c:plotArea", NS) if chart_el is not None else None
                chart_types: list[str] = []
                series: list[dict[str, str]] = []
                if plot is not None:
                    for chart_node in list(plot):
                        node_name = _chart_node_name(chart_node)
                        if not node_name.endswith("Chart"):
                            continue
                        chart_types.append(node_name)
                        for ser in chart_node.findall("c:ser", NS):
                            series.append(
                                {
                                    "chart_type": node_name,
                                    "name": _series_name(ser),
                                    "cat": _formula(ser.find("c:cat", NS)),
                                    "val": _formula(ser.find("c:val", NS)),
                                }
                            )
                out.append(
                    {
                        "sheet": sheet_name,
                        "title": _title_text(chart_el.find("c:title", NS))
                        if chart_el is not None
                        else "",
                        "chart_types": chart_types,
                        "series": series,
                        "chart_part": chart_part,
                    }
                )
    return out


def main() -> int:
    args = _parse_args()
    repo_root = repo_root_from_script(__file__)
    template = (repo_root / args.template).resolve()
    chart_spec_path = (repo_root / args.chart_spec).resolve()
    out_md = (repo_root / args.out_md).resolve()
    out_json = (repo_root / args.out_json).resolve()

    template_charts = _template_charts(template)
    chart_spec = json.loads(chart_spec_path.read_text(encoding="utf-8"))
    spec_charts = chart_spec.get("charts", [])

    payload = {
        "template": str(template),
        "chart_spec": str(chart_spec_path),
        "template_chart_count": len(template_charts),
        "spec_chart_count": len(spec_charts),
        "template_charts": template_charts,
        "spec_charts": [
            {
                "chart_id": c.get("chart_id"),
                "sheet": c.get("sheet"),
                "title": c.get("title"),
                "chart_type": c.get("chart_type"),
                "series": [s.get("field") for s in c.get("series_plan", [])],
            }
            for c in spec_charts
        ],
    }

    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Template Chart Audit v04",
        "",
        f"- template_chart_count: {payload['template_chart_count']}",
        f"- spec_chart_count: {payload['spec_chart_count']}",
        "",
        "| sheet | template_title | template_types | template_series |",
        "|---|---|---|---|",
    ]
    for chart in template_charts:
        series_names = ", ".join(s["name"] for s in chart["series"])
        lines.append(
            f"| {chart['sheet']} | {chart['title']} | {', '.join(chart['chart_types'])} | {series_names} |"
        )

    lines += [
        "",
        "## v04 chart spec",
        "",
        "| chart_id | sheet | chart_type | series |",
        "|---|---|---|---|",
    ]
    for chart in payload["spec_charts"]:
        lines.append(
            f"| {chart['chart_id']} | {chart['sheet']} | {chart['chart_type']} | {', '.join(chart['series'])} |"
        )
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"[AUDIT] Template charts: {payload['template_chart_count']}")
    print(f"[AUDIT] Spec charts:     {payload['spec_chart_count']}")
    print(f"[AUDIT] MD: {out_md}")
    print(f"[AUDIT] JSON: {out_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
