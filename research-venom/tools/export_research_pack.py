#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from path_config import cfg_get, load_pipeline_config

SENSITIVE_EXTENSIONS = {".pem", ".key", ".p12", ".pfx", ".crt", ".cer"}
SENSITIVE_NAME_PARTS = ("secret", "token", "credential")


def load_manifest(manifest_path: Path) -> list[str]:
    patterns: list[str] = []
    for raw in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        patterns.append(line)
    return patterns


def is_sensitive_path(rel_posix: str) -> bool:
    rel_low = rel_posix.lower()
    name = Path(rel_posix).name.lower()

    if "/secrets/" in f"/{rel_low}/":
        return True
    if name == ".env" or name.startswith(".env."):
        return True
    if Path(name).suffix.lower() in SENSITIVE_EXTENSIONS:
        return True
    if any(part in name for part in SENSITIVE_NAME_PARTS):
        return True
    return False


def discover(repo_root: Path, patterns: Iterable[str]) -> tuple[list[Path], list[str]]:
    matched: set[Path] = set()
    blocked: set[str] = set()
    for pattern in patterns:
        for p in repo_root.glob(pattern):
            if not p.is_file():
                continue
            rel = p.relative_to(repo_root).as_posix()
            if rel.endswith(":Zone.Identifier"):
                continue
            if is_sensitive_path(rel):
                blocked.add(rel)
                continue
            matched.add(p)
    return sorted(matched), sorted(blocked)


def copy_files(repo_root: Path, files: list[Path], out_root: Path) -> list[str]:
    copied: list[str] = []
    for src in files:
        rel = src.relative_to(repo_root)
        dst = out_root / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append(rel.as_posix())
    return copied


def map_dest_rel(repo_root: Path, src: Path, strip_prefix: str) -> Path:
    rel = src.relative_to(repo_root).as_posix()
    prefix = strip_prefix.strip().strip("/")
    if not prefix:
        return Path(rel)
    if rel == prefix:
        return Path(".")
    prefix_slash = prefix + "/"
    if rel.startswith(prefix_slash):
        return Path(rel[len(prefix_slash) :])
    raise ValueError(f"source path '{rel}' does not match strip-prefix '{prefix}'")


def copy_files_mapped(
    repo_root: Path, files: list[Path], out_root: Path, strip_prefix: str
) -> list[tuple[str, str]]:
    copied: list[tuple[str, str]] = []
    for src in files:
        src_rel = src.relative_to(repo_root).as_posix()
        dst_rel_path = map_dest_rel(repo_root, src, strip_prefix)
        if str(dst_rel_path) in ("", "."):
            continue
        dst = out_root / dst_rel_path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied.append((src_rel, dst_rel_path.as_posix()))
    return copied


def write_report(
    out_root: Path,
    manifest_ref: str,
    copied_pairs: list[tuple[str, str]],
    missing_patterns: list[str],
    strip_prefix: str,
    blocked_sensitive: list[str],
) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    report = {
        "generated_at": ts,
        "manifest": manifest_ref,
        "strip_prefix": strip_prefix,
        "files_copied": len(copied_pairs),
        "missing_patterns": missing_patterns,
        "blocked_sensitive_files": blocked_sensitive,
        "copied_files": [{"source": s, "destination": d} for s, d in copied_pairs],
    }
    report_json = out_root / "export_report.json"
    report_md = out_root / "export_report.md"
    report_json.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# Research Export Report",
        "",
        f"- generated_at: {ts}",
        f"- manifest: `{manifest_ref}`",
        f"- strip_prefix: `{strip_prefix}`",
        f"- files_copied: {len(copied_pairs)}",
        f"- missing_patterns: {len(missing_patterns)}",
        f"- blocked_sensitive_files: {len(blocked_sensitive)}",
        "",
    ]
    if missing_patterns:
        lines.append("## Missing Patterns")
        for p in missing_patterns:
            lines.append(f"- `{p}`")
        lines.append("")
    if blocked_sensitive:
        lines.append("## Blocked Sensitive Files")
        for p in blocked_sensitive:
            lines.append(f"- `{p}`")
        lines.append("")
    lines.append("## Copied Files")
    for src_rel, dst_rel in copied_pairs:
        lines.append(f"- `{src_rel}` -> `{dst_rel}`")
    report_md.write_text("\n".join(lines), encoding="utf-8")


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root_default = script_dir.parent
    config_default = repo_root_default / "config" / "process_pipeline_v01.json"

    p = argparse.ArgumentParser(
        description="Export minimal 205 research pack by whitelist manifest."
    )
    p.add_argument(
        "--config",
        default=str(config_default),
        help="Central pipeline config path.",
    )
    p.add_argument(
        "--profile",
        default="full",
        choices=["full", "scripts_review"],
        help="Export profile from config.profiles.export (fallback: config.export_profiles).",
    )
    p.add_argument(
        "--repo-root", default=str(repo_root_default), help="Repository root path."
    )
    p.add_argument(
        "--manifest",
        default="",
        help="Optional config or manifest path (overrides --config/--profile).",
    )
    p.add_argument(
        "--out-dir",
        default="",
        help="Output directory for export package. Default: /home/ubuntu/exports/research-venom-pack_<timestamp>",
    )
    p.add_argument(
        "--strip-prefix",
        default="",
        help="Prefix removed from source paths when writing destination tree.",
    )
    p.add_argument(
        "--dry-run", action="store_true", help="Show selection only, do not copy files."
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(args.repo_root).resolve()
    if not repo_root.exists():
        raise SystemExit(f"repo root not found: {repo_root}")

    if args.out_dir:
        out_root = Path(args.out_dir).resolve()
    else:
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        out_root = Path("/home/ubuntu/exports") / f"research-venom-pack_{stamp}"

    patterns: list[str]
    manifest_label = ""
    if (args.manifest or "").strip():
        manifest = Path(args.manifest).resolve()
        if not manifest.exists():
            raise SystemExit(f"manifest not found: {manifest}")
        patterns = load_manifest(manifest)
        manifest_label = str(manifest)
    else:
        cfg = load_pipeline_config(args.config, __file__)
        patterns = cfg_get(cfg, "profiles", "export", args.profile, default=[]) or []
        source_label = "profiles.export"
        if not patterns:
            patterns = cfg_get(cfg, "export_profiles", args.profile, default=[]) or []
            source_label = "export_profiles"
        if not patterns:
            raise SystemExit(
                f"Missing export profile '{args.profile}' in config (profiles/export_profiles): {args.config}"
            )
        manifest_label = (
            f"{Path(args.config).resolve()}::{source_label}::{args.profile}"
        )

    files, blocked_sensitive = discover(repo_root, patterns)

    missing_patterns: list[str] = []
    rel_set = {p.relative_to(repo_root).as_posix() for p in files}
    for pat in patterns:
        if not any(Path(rel).match(pat) for rel in rel_set):
            missing_patterns.append(pat)

    print(f"[EXPORT] repo_root={repo_root}")
    print(f"[EXPORT] profile_source={manifest_label}")
    print(f"[EXPORT] matched_files={len(files)}")
    if missing_patterns:
        print(f"[EXPORT] missing_patterns={len(missing_patterns)}")
    if blocked_sensitive:
        print(f"[EXPORT] blocked_sensitive_files={len(blocked_sensitive)}")

    if args.dry_run:
        for p in files:
            src_rel = p.relative_to(repo_root).as_posix()
            dst_rel = map_dest_rel(repo_root, p, args.strip_prefix).as_posix()
            print(f"{src_rel}\t=>\t{dst_rel}")
        if blocked_sensitive:
            print("[EXPORT] blocked_sensitive_list:")
            for rel in blocked_sensitive:
                print(rel)
        return 0

    if out_root.exists():
        raise SystemExit(f"out-dir already exists: {out_root}")
    out_root.mkdir(parents=True, exist_ok=False)

    copied_pairs = copy_files_mapped(repo_root, files, out_root, args.strip_prefix)
    write_report(
        out_root,
        manifest_label,
        copied_pairs,
        missing_patterns,
        args.strip_prefix,
        blocked_sensitive,
    )
    print(f"[EXPORT] out_dir={out_root}")
    print("[EXPORT] report: export_report.json / export_report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
