#!/usr/bin/env python3
"""
Generate Buildroot external python package recipes for binary-refinery optional
dependencies that are not already covered by Buildroot core packages.

This script:
1) Reads requirements from buildroot-external/package/python-binary-refinery/requirements-all.txt
2) Adds a LIEF requirement pin
3) Compares against buildroot package/python-* coverage
4) Creates missing package recipes under buildroot-external/package/python-*/
5) Updates buildroot-external/package/refinery-generated-deps/Config.in
6) Ensures buildroot-external/Config.in sources that generated Config.in
"""

from __future__ import annotations

import argparse
import io
import json
import os
import re
import tarfile
import textwrap
import urllib.request
import urllib.error
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
WORK_DIR = ROOT / ".work" / "buildroot"
SRC_PARENT = WORK_DIR / "src"
EXTERNAL_DIR = ROOT / "buildroot-external"
REQ_FILE = EXTERNAL_DIR / "package" / "python-binary-refinery" / "requirements-all.txt"
ROOT_CONFIG_IN = EXTERNAL_DIR / "Config.in"
GENERATED_MENU = EXTERNAL_DIR / "package" / "refinery-generated-deps" / "Config.in"


def normalize_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]", "", name.lower())


def parse_requirement_name(requirement_line: str) -> str:
    req_name = requirement_line.split(";", 1)[0]
    req_name = req_name.split("[", 1)[0]
    req_name = re.split(r"[<>=!~]", req_name, 1)[0]
    req_name = req_name.strip().lower()
    return req_name


def parse_requirement_spec(requirement_line: str) -> str:
    req_name = parse_requirement_name(requirement_line)
    tail = requirement_line.split(";", 1)[0].strip()
    spec = tail[len(req_name) :]
    return spec.strip()


def normalize_pkg_for_dir(req_name: str) -> str:
    name = req_name.strip().lower().replace("_", "-")
    if not name.startswith("python-"):
        name = f"python-{name}"
    return name


def symbol_from_pkg_dir(pkg_dir_name: str) -> str:
    return "BR2_PACKAGE_" + re.sub(r"[^A-Z0-9_]", "_", pkg_dir_name.upper().replace("-", "_"))


def var_prefix_from_pkg_dir(pkg_dir_name: str) -> str:
    base = pkg_dir_name[len("python-") :]
    base = re.sub(r"[^A-Z0-9_]", "_", base.upper().replace("-", "_"))
    return f"PYTHON_{base}"


def urlopen_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=30) as resp:
        return json.load(resp)


def download_bytes(url: str) -> bytes:
    with urllib.request.urlopen(url, timeout=60) as resp:
        return resp.read()


def version_key(version: str):
    # Best-effort semantic-ish key without external deps.
    parts = re.split(r"[.-]", version)
    key: list[tuple[int, object]] = []
    for p in parts:
        if p.isdigit():
            key.append((0, int(p)))
        else:
            key.append((1, p))
    return tuple(key)


def satisfies(version: str, spec: str) -> bool:
    spec = spec.strip()
    if not spec:
        return True
    for clause in [s.strip() for s in spec.split(",") if s.strip()]:
        if clause.startswith("=="):
            if version != clause[2:].strip():
                return False
        elif clause.startswith(">="):
            if version_key(version) < version_key(clause[2:].strip()):
                return False
        elif clause.startswith("<="):
            if version_key(version) > version_key(clause[2:].strip()):
                return False
        elif clause.startswith(">"):
            if version_key(version) <= version_key(clause[1:].strip()):
                return False
        elif clause.startswith("<"):
            if version_key(version) >= version_key(clause[1:].strip()):
                return False
    return True


def choose_version(info: dict, spec: str) -> str:
    releases = info.get("releases", {}) or {}
    versions = [v for v in releases.keys() if releases.get(v)]
    if not versions:
        return info["info"]["version"]
    candidates = sorted((v for v in versions if satisfies(v, spec)), key=version_key)
    if candidates:
        return candidates[-1]
    return info["info"]["version"]


def choose_sdist(release_files: Iterable[dict]) -> dict | None:
    for f in release_files:
        if f.get("packagetype") == "sdist":
            return f
    return None


def detect_setup_type_from_sdist(url: str) -> str:
    try:
        blob = download_bytes(url)
    except Exception:
        return "setuptools"

    def inspect_pyproject(data: bytes) -> str:
        text = data.decode("utf-8", errors="ignore")
        backend = ""
        for line in text.splitlines():
            line = line.strip()
            if line.startswith("build-backend"):
                _, rhs = line.split("=", 1)
                backend = rhs.strip().strip("'\"")
                break
        if "setuptools.build_meta" in backend:
            return "setuptools"
        if "flit_core.buildapi" in backend:
            return "flit"
        if backend:
            return "pep517"
        return "pep517"

    if url.endswith(".zip"):
        with zipfile.ZipFile(io.BytesIO(blob)) as zf:
            names = zf.namelist()
            pyproject = next((n for n in names if n.endswith("/pyproject.toml") or n == "pyproject.toml"), None)
            if pyproject:
                return inspect_pyproject(zf.read(pyproject))
            setup_py = next((n for n in names if n.endswith("/setup.py") or n == "setup.py"), None)
            if setup_py:
                return "setuptools"
            return "pep517"

    mode = "r:gz"
    if url.endswith(".tar.bz2"):
        mode = "r:bz2"
    elif url.endswith(".tar.xz"):
        mode = "r:xz"
    with tarfile.open(fileobj=io.BytesIO(blob), mode=mode) as tf:
        members = tf.getnames()
        pyproject = next((n for n in members if n.endswith("/pyproject.toml") or n == "pyproject.toml"), None)
        if pyproject:
            data = tf.extractfile(pyproject)
            if data is None:
                return "pep517"
            return inspect_pyproject(data.read())
        setup_py = next((n for n in members if n.endswith("/setup.py") or n == "setup.py"), None)
        if setup_py:
            return "setuptools"
    return "pep517"


def load_buildroot_python_norms(buildroot_src: Path) -> set[str]:
    norms: set[str] = set()
    for d in sorted((buildroot_src / "package").glob("python-*")):
        if not d.is_dir():
            continue
        base = d.name[len("python-") :]
        norm = normalize_name(base)
        if not norm:
            continue
        norms.add(norm)
        if norm.startswith("python") and len(norm) > 6:
            norms.add(norm[6:])
    return norms


def ensure_buildroot_source(version: str) -> Path:
    src = SRC_PARENT / f"buildroot-{version}"
    if src.exists():
        return src
    SRC_PARENT.mkdir(parents=True, exist_ok=True)
    archive = WORK_DIR / f"buildroot-{version}.tar.xz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        url = f"https://buildroot.org/downloads/buildroot-{version}.tar.xz"
        print(f"Downloading {url}")
        blob = download_bytes(url)
        archive.write_bytes(blob)
    with tarfile.open(archive, "r:xz") as tf:
        tf.extractall(SRC_PARENT)
    return src


@dataclass
class PackageRecipe:
    requirement: str
    project_name: str
    spec: str
    pkg_dir_name: str
    version: str
    source_filename: str
    site: str
    sha256: str
    setup_type: str
    summary: str
    home_page: str
    license_name: str


def pypi_project_candidates(req_name: str) -> list[str]:
    cands = []
    cands.append(req_name)
    cands.append(req_name.replace("_", "-"))
    cands.append(req_name.replace("-", "_"))
    seen = set()
    out = []
    for c in cands:
        cl = c.lower()
        if cl in seen:
            continue
        seen.add(cl)
        out.append(c)
    return out


def fetch_recipe(requirement: str, req_name: str) -> PackageRecipe:
    spec = parse_requirement_spec(requirement)
    pkg_dir_name = normalize_pkg_for_dir(req_name)

    last_err: Exception | None = None
    meta = None
    selected_project = None
    for project in pypi_project_candidates(req_name):
        url = f"https://pypi.org/pypi/{project}/json"
        try:
            meta = urlopen_json(url)
            selected_project = project
            break
        except Exception as exc:  # noqa: BLE001
            last_err = exc
    if meta is None or selected_project is None:
        raise RuntimeError(f"Failed to fetch PyPI metadata for {requirement}: {last_err}")

    version = choose_version(meta, spec)
    release_files = meta.get("releases", {}).get(version, [])
    sdist = choose_sdist(release_files)
    if not sdist:
        # fallback to latest sdist if chosen version has no sdist
        for candidate in sorted(meta.get("releases", {}).keys(), key=version_key, reverse=True):
            rel_files = meta.get("releases", {}).get(candidate, [])
            sdist = choose_sdist(rel_files)
            if sdist:
                version = candidate
                release_files = rel_files
                break
    if not sdist:
        raise RuntimeError(f"No sdist available on PyPI for {requirement}")

    source_filename = sdist["filename"]
    source_url = sdist["url"]
    site = source_url.rsplit("/", 1)[0]
    sha256 = sdist.get("digests", {}).get("sha256", "")
    setup_type = detect_setup_type_from_sdist(source_url)

    info = meta.get("info", {})
    summary = (info.get("summary") or "").strip() or "Auto-generated Buildroot package."
    home_page = (info.get("home_page") or info.get("project_url") or "").strip() or f"https://pypi.org/project/{selected_project}/"
    license_name = (info.get("license") or "").strip() or "UNKNOWN"

    return PackageRecipe(
        requirement=requirement,
        project_name=selected_project.lower(),
        spec=spec,
        pkg_dir_name=pkg_dir_name,
        version=version,
        source_filename=source_filename,
        site=site,
        sha256=sha256,
        setup_type=setup_type,
        summary=summary,
        home_page=home_page,
        license_name=license_name,
    )


def write_recipe(recipe: PackageRecipe) -> None:
    pkg_dir = EXTERNAL_DIR / "package" / recipe.pkg_dir_name
    pkg_dir.mkdir(parents=True, exist_ok=True)

    symbol = symbol_from_pkg_dir(recipe.pkg_dir_name)
    var = var_prefix_from_pkg_dir(recipe.pkg_dir_name)

    config_in = textwrap.dedent(
        f"""\
        config {symbol}
        \tbool "{recipe.pkg_dir_name}"
        \tdepends on BR2_PACKAGE_PYTHON3
        \thelp
        \t  {recipe.summary}
        \t
        \t  {recipe.home_page}
        """
    )

    mk = textwrap.dedent(
        f"""\
        ################################################################################
        #
        # {recipe.pkg_dir_name}
        #
        ################################################################################

        {var}_VERSION = {recipe.version}
        {var}_SOURCE = {recipe.source_filename}
        {var}_SITE = {recipe.site}
        {var}_SETUP_TYPE = {recipe.setup_type}
        {var}_LICENSE = {recipe.license_name}

        $(eval $(python-package))
        """
    )

    hash_lines = [
        f"# sha256 from {recipe.site}",
    ]
    if recipe.sha256:
        hash_lines.append(f"sha256  {recipe.sha256}  {recipe.source_filename}")
    hash_text = "\n".join(hash_lines) + "\n"

    (pkg_dir / "Config.in").write_text(config_in, encoding="utf-8")
    (pkg_dir / f"{recipe.pkg_dir_name}.mk").write_text(mk, encoding="utf-8")
    (pkg_dir / f"{recipe.pkg_dir_name}.hash").write_text(hash_text, encoding="utf-8")


def update_generated_menu(generated_packages: list[str]) -> None:
    GENERATED_MENU.parent.mkdir(parents=True, exist_ok=True)
    lines = []
    for pkg in sorted(generated_packages):
        lines.append(f'source "$BR2_EXTERNAL_TRIAGEBOX_PATH/package/{pkg}/Config.in"')
    GENERATED_MENU.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")

    root_text = ROOT_CONFIG_IN.read_text(encoding="utf-8")
    include_line = 'source "$BR2_EXTERNAL_TRIAGEBOX_PATH/package/refinery-generated-deps/Config.in"'
    if include_line not in root_text:
        root_text = root_text.replace(
            'source "$BR2_EXTERNAL_TRIAGEBOX_PATH/package/python-binary-refinery/Config.in"\n',
            'source "$BR2_EXTERNAL_TRIAGEBOX_PATH/package/python-binary-refinery/Config.in"\n'
            f"\t{include_line}\n",
        )
        ROOT_CONFIG_IN.write_text(root_text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--buildroot-version", default="2026.02-rc1")
    parser.add_argument("--lief-version", default="0.17.3")
    args = parser.parse_args()

    if not REQ_FILE.exists():
        raise SystemExit(f"Missing requirements file: {REQ_FILE}")

    buildroot_src = ensure_buildroot_source(args.buildroot_version)
    covered_norms = load_buildroot_python_norms(buildroot_src)

    reqs = [
        line.strip()
        for line in REQ_FILE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    reqs.append(f"lief=={args.lief_version}")

    to_generate: list[tuple[str, str]] = []
    covered = 0
    for req in reqs:
        req_name = parse_requirement_name(req)
        req_norm = normalize_name(req_name)
        alt_norm = req_norm[6:] if req_norm.startswith("python") and len(req_norm) > 6 else ""
        if req_norm in covered_norms or (alt_norm and alt_norm in covered_norms):
            covered += 1
            continue
        to_generate.append((req, req_name))

    print(f"requirements total={len(reqs)} covered={covered} missing={len(to_generate)}")

    generated_dirs: list[str] = []
    failures: list[str] = []
    for req, req_name in to_generate:
        try:
            recipe = fetch_recipe(req, req_name)
            write_recipe(recipe)
            generated_dirs.append(recipe.pkg_dir_name)
            print(f"generated {recipe.pkg_dir_name} ({recipe.version})")
        except Exception as exc:  # noqa: BLE001
            failures.append(f"{req}: {exc}")
            print(f"FAILED {req}: {exc}")

    update_generated_menu(generated_dirs)

    if failures:
        print("\nFailed to generate some recipes:")
        for f in failures:
            print(f"  - {f}")
        return 2

    print("\nAll missing recipes generated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
