#!/usr/bin/env python3
import json
import re
import subprocess
import sys


def main():
    result = subprocess.run(
        ["codex", "debug", "models"], capture_output=True, text=True, check=True
    )
    models = json.loads(result.stdout).get("models", [])
    available = sorted(
        (model for model in models if model.get("visibility") == "list"),
        key=lambda model: model.get("priority", 9999),
    )
    slugs = [model.get("slug", "") for model in available]
    if not slugs or any(not re.fullmatch(r"[A-Za-z0-9._-]+", slug) for slug in slugs):
        raise ValueError("Codex returned an empty or invalid model catalog")
    print("\n".join(slugs))


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError, ValueError) as exc:
        print(f"error: could not load Codex models: {exc}", file=sys.stderr)
        sys.exit(1)
