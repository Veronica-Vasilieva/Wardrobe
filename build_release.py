#!/usr/bin/env python3
"""
Wardrobe release builder.

Reads the version from Wardrobe.toc, verifies it matches the Lua banner /
ADDON_VERSION constant / load-print message and that CHANGELOG.md has an
entry for it, then builds dist/Wardrobe-vX.Y.zip. With --release it also
clones the repo, syncs the addon files, commits, pushes, deletes the
previous GitHub release (and its tag), and creates the new one with the
zip attached and release notes pulled from the CHANGELOG entry.

Modes:
  python build_release.py
      Build the zip only. No git, no GitHub. Useful for a sanity check.

  python build_release.py --release
      Full release flow. Notes auto-extracted from CHANGELOG.md.

  python build_release.py --release --notes "Short note"
  python build_release.py --release --notes-file notes.md
      Override the auto-extracted notes.

Prerequisites: `python` (>=3.8), `git`, `gh` (logged in), and PowerShell
(for Compress-Archive on Windows; on other OSes we fall back to
shutil.make_archive which produces the same layout).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ADDON_ROOT = Path(__file__).resolve().parent
ADDON_NAME = "Wardrobe"
REPO       = "Veronica-Vasilieva/Wardrobe"

# Files/dirs that exist in the working folder but should NOT ship in the
# release zip or be synced into the git repo clone.
EXCLUDED = {
    "dist", ".git", ".gitignore", "__pycache__", "build_release.py",
    # README screenshots and other repo-only docs assets — kept in git but
    # not shipped to players (they only need files that load in-game).
    "docs",
}


# ---------------------------------------------------------------- helpers

def fail(msg):
    sys.stderr.write("error: " + msg + "\n")
    sys.exit(1)


def info(msg):
    sys.stdout.write(msg + "\n")
    sys.stdout.flush()


def run(cmd, cwd=None, capture=False, check=True):
    """Run a subprocess, echo the command, optionally capture output."""
    info("  $ " + " ".join(str(c) for c in cmd))
    res = subprocess.run(
        cmd, cwd=cwd, check=check, capture_output=capture, text=True,
    )
    return res


def check_tool(name, args=("--version",)):
    """Verify a CLI tool is present and runnable."""
    try:
        subprocess.run([name, *args], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        fail(f"`{name}` not found or not working. Install it and try again.")


# ----------------------------------------------------------- version sanity

def read_toc_version():
    toc = (ADDON_ROOT / f"{ADDON_NAME}.toc").read_text(encoding="utf-8")
    m = re.search(r"^##\s*Version:\s*(.+)\s*$", toc, re.MULTILINE)
    if not m:
        fail("Could not find `## Version: ...` in .toc")
    return m.group(1).strip()


def verify_versions(version):
    """Make sure the version appears consistently in all the places we
    put it. Bumping one and forgetting the others has bitten us before."""
    lua = (ADDON_ROOT / f"{ADDON_NAME}.lua").read_text(encoding="utf-8")
    v   = re.escape(version)

    # The load message uses Print("v" .. ADDON_VERSION .. ...) so checking
    # the ADDON_VERSION constant covers it transitively. The banner comment
    # is a literal string we have to bump manually.
    checks = [
        (rf"--\s+{re.escape(ADDON_NAME)}\s+v{v}\b",
            "Lua banner comment (top of file)"),
        (rf'ADDON_VERSION\s*=\s*"{v}"',
            "ADDON_VERSION constant"),
    ]
    for pattern, label in checks:
        if not re.search(pattern, lua):
            fail(f"{label} does not match v{version}. "
                 f"Bump it before releasing.")


def verify_changelog(version):
    ch = (ADDON_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if f"## [{version}]" not in ch:
        fail(f"CHANGELOG.md has no `## [{version}]` section. "
             f"Add one before releasing.")


def extract_changelog_notes(version):
    """Return the markdown body of the [version] CHANGELOG entry, or None."""
    ch = (ADDON_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    # Capture between "## [VERSION] ..." and the next "## [" header (or EOF).
    pattern = (
        rf"##\s*\[{re.escape(version)}\][^\n]*\n"
        r"(.*?)"
        r"(?=\n##\s*\[|\Z)"
    )
    m = re.search(pattern, ch, flags=re.DOTALL)
    if not m:
        return None
    return m.group(1).strip()


# --------------------------------------------------------------- build zip

def build_zip(version, out_dir):
    """Build dist/Wardrobe-vX.Y.zip with a top-level Wardrobe/ folder
    matching what players need to extract into Interface/AddOns/."""
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        staging  = tmp_path / ADDON_NAME
        shutil.copytree(
            ADDON_ROOT, staging,
            ignore=shutil.ignore_patterns(*EXCLUDED, "*.pyc", "*.zip"),
        )
        zip_base = out_dir / f"{ADDON_NAME}-v{version}"
        # shutil.make_archive produces zip_base.zip with `ADDON_NAME/` as
        # the top-level entry (because base_dir=ADDON_NAME, root_dir=tmp).
        zip_path = shutil.make_archive(
            base_name=str(zip_base),
            format="zip",
            root_dir=tmp,
            base_dir=ADDON_NAME,
        )
        return Path(zip_path)


# ------------------------------------------------------- github / git flow

def find_previous_release(current_tag):
    """Most recent GitHub release whose tag isn't current_tag."""
    res = run(
        ["gh", "release", "list", "--repo", REPO,
         "--limit", "10", "--json", "tagName"],
        capture=True, check=False,
    )
    if res.returncode != 0:
        return None
    try:
        rows = json.loads(res.stdout)
    except json.JSONDecodeError:
        return None
    for r in rows:
        if r.get("tagName") and r["tagName"] != current_tag:
            return r["tagName"]
    return None


def sync_repo(clone_dir):
    """Copy everything except EXCLUDED entries from ADDON_ROOT into
    clone_dir, replacing any existing files. Removes files/dirs in
    clone_dir that no longer exist locally (so deletions propagate)."""
    # Remove tracked files/dirs in clone_dir that aren't in local (and
    # aren't .git). Mirror direction: local -> clone.
    for p in clone_dir.iterdir():
        if p.name == ".git" or p.name in EXCLUDED:
            continue
        local = ADDON_ROOT / p.name
        if not local.exists():
            if p.is_dir():
                shutil.rmtree(p)
            else:
                p.unlink()
    # Copy local entries into the clone.
    for p in ADDON_ROOT.iterdir():
        if p.name in EXCLUDED or p.name.endswith(".pyc") or p.name.endswith(".zip"):
            continue
        dest = clone_dir / p.name
        if p.is_file():
            shutil.copy2(p, dest)
        elif p.is_dir():
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(p, dest)


def do_release(version, zip_path, notes):
    tag = f"v{version}"
    prev_tag = find_previous_release(tag)
    info(f"Previous release: {prev_tag or '(none)'}")

    with tempfile.TemporaryDirectory() as tmp:
        clone_dir = Path(tmp) / ADDON_NAME
        info("Cloning repo...")
        run(["git", "clone", f"https://github.com/{REPO}.git", str(clone_dir)])

        info("Syncing local files into clone...")
        sync_repo(clone_dir)

        # Anything changed?
        status = run(
            ["git", "status", "--porcelain"],
            cwd=clone_dir, capture=True,
        ).stdout
        if status.strip():
            info("Committing and pushing...")
            git_env = [
                "-c", "user.name=Veronica-Vasilieva",
                "-c", "user.email=noreply@github.com",
            ]
            commit_msg = (
                f"release: v{version}\n\n"
                f"See CHANGELOG.md for details.\n\n"
                f"Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
            )
            run(["git", *git_env, "add", "."], cwd=clone_dir)
            run(["git", *git_env, "commit", "-m", commit_msg], cwd=clone_dir)
            run(["git", "push"], cwd=clone_dir)
        else:
            info("(no file changes to push)")

        if prev_tag:
            info(f"Deleting previous release {prev_tag}...")
            run(
                ["gh", "release", "delete", prev_tag, "--repo", REPO,
                 "--yes", "--cleanup-tag"],
                check=False,
            )

        info(f"Creating release {tag}...")
        run([
            "gh", "release", "create", tag, str(zip_path),
            "--repo", REPO,
            "--title", f"{ADDON_NAME} v{version}",
            "--notes", notes,
            "--latest",
        ])

    info(f"\nReleased: https://github.com/{REPO}/releases/tag/{tag}")


# ------------------------------------------------------------------ main

def main():
    ap = argparse.ArgumentParser(
        description="Build (and optionally release) a Wardrobe version.",
    )
    ap.add_argument(
        "--release", action="store_true",
        help="After building, push and create a GitHub release."
    )
    ap.add_argument(
        "--notes", default=None,
        help="Release notes text. Overrides the CHANGELOG auto-extract.",
    )
    ap.add_argument(
        "--notes-file", default=None,
        help="Path to a file with release notes (overrides --notes).",
    )
    ap.add_argument(
        "--version", default=None,
        help="Override the version (otherwise read from .toc).",
    )
    args = ap.parse_args()

    version = args.version or read_toc_version()
    info("=" * 50)
    info(f"  {ADDON_NAME} release builder")
    info("=" * 50)
    info(f"  Version: {version}")
    info("")

    info("Verifying version consistency...")
    verify_versions(version)
    verify_changelog(version)
    info("  OK\n")

    out_dir  = ADDON_ROOT / "dist"
    info("Building zip...")
    zip_path = build_zip(version, out_dir)
    info(f"  -> {zip_path}\n")

    if not args.release:
        info("Done (build only). Pass --release to push & publish.")
        return

    check_tool("git", ("--version",))
    check_tool("gh",  ("--version",))

    if args.notes_file:
        notes = Path(args.notes_file).read_text(encoding="utf-8")
        info(f"Notes loaded from {args.notes_file}")
    elif args.notes:
        notes = args.notes
        info("Notes from --notes flag")
    else:
        notes = extract_changelog_notes(version)
        if not notes:
            fail(
                f"Could not auto-extract notes from CHANGELOG.md for v{version}. "
                f"Pass --notes or --notes-file."
            )
        info(f"Notes auto-extracted from CHANGELOG.md ({len(notes)} chars)")

    info("")
    do_release(version, zip_path, notes)


if __name__ == "__main__":
    main()
