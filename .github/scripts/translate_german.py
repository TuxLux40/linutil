#!/usr/bin/env python3
"""Detect German in commit messages and code comments, translate to English."""

import os
import sys
import subprocess
from pathlib import Path

import requests
from langdetect import detect, DetectorFactory, LangDetectException

DetectorFactory.seed = 0  # deterministic results

DEEPL_KEY = os.environ.get("DEEPL_API_KEY", "")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_REPO = os.environ.get("GITHUB_REPOSITORY", "")
PR_NUMBER = os.environ.get("PR_NUMBER", "")
PR_TITLE = os.environ.get("PR_TITLE", "")
EVENT_NAME = os.environ.get("EVENT_NAME", "push")

# Single-line comment prefixes per file extension
COMMENT_PREFIXES: dict[str, str] = {
    ".sh": "#", ".bash": "#", ".zsh": "#", ".fish": "#",
    ".py": "#", ".rb": "#", ".pl": "#", ".r": "#",
    ".js": "//", ".ts": "//", ".tsx": "//", ".jsx": "//",
    ".go": "//", ".rs": "//", ".c": "//", ".cpp": "//",
    ".h": "//", ".hpp": "//", ".java": "//", ".kt": "//",
    ".lua": "--", ".sql": "--",
}


def is_german(text: str) -> bool:
    text = text.strip()
    # Need at least 2 words for reliable detection
    if len(text.split()) < 2:
        return False
    try:
        return detect(text) == "de"
    except LangDetectException:
        return False


def translate(text: str) -> str:
    if not DEEPL_KEY:
        print("WARNING: DEEPL_API_KEY not set — skipping translation", file=sys.stderr)
        return text
    r = requests.post(
        "https://api-free.deepl.com/v2/translate",
        data={"auth_key": DEEPL_KEY, "text": text, "source_lang": "DE", "target_lang": "EN-US"},
        timeout=15,
    )
    r.raise_for_status()
    return r.json()["translations"][0]["text"]


def find_comment_start(line: str, prefix: str) -> int:
    """Return index where comment prefix starts, skipping occurrences inside quotes."""
    in_single = in_double = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and (in_single or in_double):
            i += 2
            continue
        if c == "'" and not in_double:
            in_single = not in_single
        elif c == '"' and not in_single:
            in_double = not in_double
        elif not in_single and not in_double:
            if line[i : i + len(prefix)] == prefix:
                return i
        i += 1
    return -1


def process_file(path: str) -> bool:
    ext = Path(path).suffix.lower()
    prefix = COMMENT_PREFIXES.get(ext)
    if not prefix:
        return False

    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except OSError:
        return False

    new_lines = []
    changed = False
    for line in lines:
        stripped = line.rstrip("\n")

        # Skip shebangs
        if prefix == "#" and stripped.lstrip().startswith("#!"):
            new_lines.append(line)
            continue

        idx = find_comment_start(stripped, prefix)
        if idx < 0:
            new_lines.append(line)
            continue

        comment_text = stripped[idx + len(prefix) :].strip()
        if not comment_text or not is_german(comment_text):
            new_lines.append(line)
            continue

        translated = translate(comment_text)
        print(f"  [{path}] {comment_text!r} -> {translated!r}")

        code_part = stripped[:idx].rstrip()
        indent = " " * (len(stripped) - len(stripped.lstrip()))
        if code_part:
            new_lines.append(f"{code_part}  {prefix} {translated}\n")
        else:
            new_lines.append(f"{indent}{prefix} {translated}\n")
        changed = True

    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    return changed


def get_changed_files() -> list[str]:
    result = subprocess.run(
        ["git", "diff", "--name-only", "HEAD~1", "HEAD"],
        capture_output=True, text=True,
    )
    files = [f for f in result.stdout.strip().splitlines() if f]
    # Fallback for first commit in repo
    if not files:
        result = subprocess.run(
            ["git", "diff-tree", "--no-commit-id", "-r", "--name-only", "HEAD"],
            capture_output=True, text=True,
        )
        files = [f for f in result.stdout.strip().splitlines() if f]
    return files


def translate_pr_title() -> None:
    if not (PR_NUMBER and PR_TITLE and GITHUB_TOKEN and GITHUB_REPO):
        return
    if not is_german(PR_TITLE):
        return
    translated = translate(PR_TITLE)
    if translated == PR_TITLE:
        return
    r = requests.patch(
        f"https://api.github.com/repos/{GITHUB_REPO}/pulls/{PR_NUMBER}",
        json={"title": translated},
        headers={"Authorization": f"Bearer {GITHUB_TOKEN}", "Accept": "application/vnd.github+json"},
        timeout=10,
    )
    r.raise_for_status()
    print(f"PR title: {PR_TITLE!r} -> {translated!r}")


def main() -> None:
    if EVENT_NAME == "pull_request":
        translate_pr_title()

    changed_files = get_changed_files()
    print(f"Scanning {len(changed_files)} changed file(s)...")

    any_changed = False
    for path in changed_files:
        if Path(path).is_file():
            if process_file(path):
                any_changed = True

    if not any_changed:
        print("No German text found.")
    else:
        print("Translations applied — workflow will commit changes.")


if __name__ == "__main__":
    main()
