#!/usr/bin/env python3
"""Print the model and effort values this Claude Code build actually accepts.

Every value is read live from the installed CLI or the local account cache, so
this does not rot when the model list changes.

  ./model-lookup.py                 models + efforts + org default
  ./model-lookup.py --efforts-only  just the effort levels
  ./model-lookup.py --probe-aliases resolve each alias by really calling the CLI
  ./model-lookup.py --check FILE    flag MODEL_n/EFFORT_n in a launch.env
  ./model-lookup.py --list-entitled bare entitled ids on stdout, for a launcher menu
"""
import json
import os
import re
import subprocess
import sys

CLAUDE_JSON = os.environ.get("CLAUDE_JSON", os.path.expanduser("~/.claude.json"))
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude")
ALIASES = ["opus", "sonnet", "haiku", "fable", "opusplan", "default"]
EFFORT_ORDER = ["low", "medium", "high", "xhigh", "max"]


def help_text():
    override = os.environ.get("HELP_FILE")
    if override:
        return open(override).read()
    return subprocess.run([CLAUDE_BIN, "--help"], capture_output=True, text=True).stdout


def efforts():
    """The --effort values, parsed from the CLI's own help.

    Bounded to the --effort option's own text. An unbounded search runs on into the
    next flag and returns its (choices: ...) list as a false success.
    """
    flat = re.sub(r"\s+", " ", help_text())
    block = re.search(r"--effort <level>(.*?)(?= --[a-z]|\Z)", flat)
    for candidate in reversed(re.findall(r"\(([^)]*)\)", block.group(1) if block else "")):
        values = [v.strip() for v in candidate.split(",")]
        if len(values) > 1 and all(re.fullmatch(r"[a-z]+", v) for v in values):
            return values
    sys.exit("error: could not find the --effort value list in `claude --help`")


def account_models():
    with open(CLAUDE_JSON) as fh:
        blob = json.load(fh)
    # The cache is written by the CLI, so a shape change there must not traceback the
    # gate reading it, and must not be dropped silently either.
    raw = blob.get("modelAccessCache") or []
    if not isinstance(raw, list):
        raw = [raw]
    rows = [r for r in raw if isinstance(r, dict) and isinstance(r.get("apiName"), str)]
    if len(rows) != len(raw):
        sys.stderr.write(f"warning: {len(raw) - len(rows)} unusable row(s) ignored in "
                         f"{CLAUDE_JSON}, the Claude CLI's own model cache\n")
    return rows, blob.get("orgModelDefaultCache") or {}


def list_entitled():
    """Bare entitled model ids, one per line, for a launcher to build its menu from.

    stdout carries nothing but ids so the caller can read it without parsing, and a
    cache it cannot use is a refusal rather than an empty menu.
    """
    try:
        rows = account_models()[0]
    except (OSError, ValueError) as err:
        sys.stderr.write(
            f"error: cannot read {CLAUDE_JSON}, the Claude CLI's own model cache: {err}\n"
            "Run claude once to refresh it.\n")
        return 1
    ids = sorted({r["apiName"] for r in rows if r.get("entitled") and r.get("apiName")})
    if not ids:
        sys.stderr.write(
            f"error: {CLAUDE_JSON}, the Claude CLI's own model cache, lists no entitled models.\n"
            "Run claude once to refresh it.\n")
        return 1
    print("\n".join(ids))
    return 0


def probe(alias):
    """Resolve one alias against the live CLI.

    An API or auth failure is not a model rejection, so the two are reported apart.
    """
    proc = subprocess.run(
        [CLAUDE_BIN, "--model", alias, "-p", "say ok", "--output-format", "json"],
        capture_output=True, text=True, stdin=subprocess.DEVNULL,
    )
    try:
        out = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return "REJECTED"
    used = ",".join(out.get("modelUsage") or {})
    if used:
        return used
    reason = out.get("terminal_reason") or "unknown"
    return f"NO ANSWER, {reason}: {str(out.get('result', ''))[:50]} (not a model rejection)"


def check(path):
    """Flag MODEL_n/EFFORT_n values a launcher would pass to the CLI.

    `restart-swarm.sh` resolves these as ${!mvar:-${MODEL:-$default}}, so a bare
    MODEL=/EFFORT= is a real fallback and an empty value is not an error. `-` reads
    stdin, so a launcher can validate values it holds before any file exists.
    """
    assign = re.compile(
        r"""\s*(?:export\s+)?(MODEL|EFFORT)(_\d+)?\s*=\s*('([^']*)'|"([^"]*)"|([^#\s]*))"""
    )
    text = sys.stdin.read() if path == "-" else open(path).read()
    models, efforts_by_n, order = {}, {}, []
    for line in text.splitlines():
        m = assign.match(line)
        if not m:
            continue
        n = m.group(2) or ""
        # Quoted values keep their spaces, because `restart-swarm.sh` sources the
        # file and ' claude-opus-5 ' really does reach --model with the spaces.
        q1, q2, bare = m.group(4, 5, 6)
        value = q1 if q1 is not None else q2 if q2 is not None else bare.strip()
        (models if m.group(1) == "MODEL" else efforts_by_n)[n] = value
        order.append((m.group(1) + n, m.group(1), n, value))

    rows = account_models()[0]
    entitled = {r["apiName"] for r in rows if r.get("entitled")}
    caps = {r["apiName"]: r["maxEffortLevel"] for r in rows if r.get("maxEffortLevel")}
    valid_efforts = efforts()
    bad = 0
    for label, kind, n, value in order:
        if not value:
            print(f"  {label}= (empty, the launcher falls back to its default)")
            continue
        note = ""
        if kind == "MODEL":
            base = re.sub(r"\[1m\]$", "", value)
            if base not in entitled and base not in ALIASES:
                note = "  <-- not an entitled model id or known alias"
        elif value not in valid_efforts:
            note = f"  <-- not one of {', '.join(valid_efforts)}; the CLI warns and silently uses the default"
        else:
            paired = re.sub(r"\[1m\]$", "", models.get(n, ""))
            if paired in ALIASES:
                note = f"  (cap not checked: {paired} resolves at runtime, prefer a concrete model id)"
            else:
                cap = caps.get(paired)
                if cap in EFFORT_ORDER and value in EFFORT_ORDER:
                    if EFFORT_ORDER.index(value) > EFFORT_ORDER.index(cap):
                        note = f"  <-- exceeds the {cap} cap for {paired}; the CLI silently downgrades it"
        bad += 1 if "<--" in note else 0
        print(f"  {label}={value}{note}")
    where = "stdin" if path == "-" else path
    print(f"\n{bad} problem(s) in {where}")
    return 1 if bad else 0


def usage(problem):
    sys.stderr.write(f"error: {problem}\n{__doc__}")
    return 2


def main():
    args = sys.argv[1:]
    if args[:1] == ["--efforts-only"]:
        print(" ".join(efforts()))
        return 0
    if args[:1] == ["--check"]:
        if len(args) < 2:
            return usage("--check needs a FILE, or - to read stdin")
        return check(args[1])
    if args[:1] == ["--list-entitled"]:
        return list_entitled()
    unknown = [a for a in args if a != "--probe-aliases"]
    if unknown:
        return usage(f"unknown option: {' '.join(unknown)}")

    models, org = account_models()
    print(f"claude {subprocess.run([CLAUDE_BIN,'--version'],capture_output=True,text=True).stdout.strip()}")
    print(f"\nEFFORT (--effort, from `claude --help`)\n  {' '.join(efforts())}")
    print("  An unknown value does NOT fail: the CLI warns and uses the default effort.")

    print(f"\nMODELS (modelAccessCache in {CLAUDE_JSON})")
    for m in sorted(models, key=lambda x: x.get("apiName", "")):
        mark = "  " if m.get("entitled") else "x "
        cap = m.get("maxEffortLevel")
        print(f"  {mark}{m.get('apiName',''):<38}{'max effort: ' + cap if cap else ''}")
    print("  x = present in this build's catalog but not entitled for this account.")
    print("  Append [1m] to a model id for a 1M context window, e.g. claude-opus-5[1m].")
    print("  This is a cache refreshed by the CLI, not a live query.")

    if org.get("name"):
        print(f"\nORG DEFAULT\n  {org['name']}  (overrides user selection: {org.get('override_user_selection')})")

    print(f"\nALIASES\n  {' '.join(ALIASES)}")
    if "--probe-aliases" in args:
        for a in ALIASES:
            print(f"  {a:<10} -> {probe(a)}")
    else:
        print("  Re-run with --probe-aliases to resolve each one against the live CLI.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
