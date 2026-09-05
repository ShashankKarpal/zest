#!/opt/homebrew/bin/python3
"""
extract-panels.py

Pulls the EXACT shell command out of each Ubersicht widget and writes it to a standalone
script in this folder (panels/). Point Zest at this folder in Settings > General >
Widget panels; until you do, Zest never runs any of them. Zest runs these scripts
verbatim so the ported panels use the identical data pipeline (same ccusage wrappers,
jq filters, plists, /tmp caches, fetch.py) as the desktop widgets. Re-run this any time
the widgets change to re-sync. It never modifies the widgets themselves.

Which widgets to extract is configuration, not code. The mapping lives in
panels/panels.local.json (gitignored, machine-specific). If it does not exist,
panels/panels.example.json is used; copy it to panels.local.json and edit the
widget paths to match your own Ubersicht setup.
"""
import json
import os
import re
import sys

HOME = os.path.expanduser("~")
WIDGETS = os.path.join(HOME, "Library/Application Support/Übersicht/widgets")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = HERE
os.makedirs(OUT, exist_ok=True)


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def extract_backtick_command(text):
    """export const command = `...` -> the ... content."""
    m = re.search(r"export\s+const\s+command\s*=\s*`", text)
    if not m:
        return None
    start = m.end()
    end = text.index("`", start)
    return text[start:end]


def extract_dquote_command(text):
    """export const command = "..." -> the ... content (single-line or wrapped)."""
    m = re.search(r"export\s+const\s+command\s*=\s*\"", text)
    if not m:
        return None
    start = m.end()
    end = text.index("\"", start)
    return text[start:end]


def extract_coffee_command(text):
    """command: \"\"\"...\"\"\" -> the ... content."""
    m = re.search(r"command:\s*\"\"\"", text)
    if not m:
        return None
    start = m.end()
    end = text.index('"""', start)
    return text[start:end]


EXTRACTORS = {
    "backtick": extract_backtick_command,
    "dquote": extract_dquote_command,
    "coffee": extract_coffee_command,
}


def load_jobs():
    for name in ("panels.local.json", "panels.example.json"):
        path = os.path.join(HERE, name)
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f), name
    print("No panels.local.json or panels.example.json found", file=sys.stderr)
    sys.exit(1)


def write(name, body):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write("#!/bin/bash\n")
        f.write(body.strip("\n") + "\n")
    os.chmod(path, 0o755)
    print(f"wrote {path} ({len(body)} bytes)")


def main():
    jobs, source = load_jobs()
    print(f"using {source}")
    ok = True
    for job in jobs:
        rel, out_name = job["widget"], job["out"]
        fn = EXTRACTORS[job["extractor"]]
        path = os.path.join(WIDGETS, rel)
        if not os.path.exists(path):
            print(f"MISSING widget: {path}", file=sys.stderr)
            ok = False
            continue
        body = fn(read(path))
        if not body:
            print(f"FAILED to extract command from {rel}", file=sys.stderr)
            ok = False
            continue
        write(out_name, body)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
