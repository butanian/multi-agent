#!/usr/bin/env python3
"""Helpers for the launcher preflight. Kept separate so the shell side needs no
heredoc temp file and no pipes: launch.sh and workspace.sh run without pipefail, so a
pipeline there would report the parser's status and hide the hook's own failure."""
import json
import os
import re
import sys

ID_OK = re.compile(r"\A[A-Za-z0-9:_-]+\Z")


def registration(path, root=""):
    """Print '<command>\t<timeout>' for the registered SessionStart command hook.

    The registration is a shell command, not a path: Claude Code expands it, and the
    real one is "$CLAUDE_PROJECT_DIR"/.claude/hooks/startup.sh. Resolving it the way the
    runtime does is the difference between gating the hook and refusing every launch.
    """
    try:
        with open(path) as handle:
            settings = json.load(handle)
    except Exception as exc:
        print("ERR\tunreadable settings: %s" % exc)
        return 1
    groups = settings.get("hooks", {}).get("SessionStart") or []
    entries = [h for g in groups for h in (g.get("hooks") or [])
               if h.get("type") == "command" and h.get("command")]
    if not entries:
        print("ERR\tno SessionStart command hook is registered")
        return 1
    command = entries[0]["command"]
    if root:
        os.environ.setdefault("CLAUDE_PROJECT_DIR", root)
        os.environ["CLAUDE_PROJECT_DIR"] = root
    resolved = os.path.expandvars(command).replace('"', "").replace("'", "").strip()
    if "$" in resolved:
        print("ERR\tregistered command still contains an unexpanded variable after "
              "resolving CLAUDE_PROJECT_DIR: %s" % resolved)
        return 1
    print("%s\t%s" % (resolved, entries[0].get("timeout", 60)))
    return 0


def pane1_settings(path):
    """Pane 1 launches with --settings <path>. Claude Code silently ignores a settings
    file that fails validation, which turns the whole deny list off and says nothing,
    so an unparseable file must stop the launch rather than quietly weaken it."""
    if not os.path.exists(path):
        print("the file pane 1 is launched with does not exist")
        return 1
    try:
        with open(path) as handle:
            json.load(handle)
    except Exception as exc:
        print("does not parse as JSON (%s); Claude Code would ignore it silently and "
              "every deny rule would be off" % exc)
        return 1
    return 0


def contract(agent, project, peers=""):
    """Validate one hook invocation. Output arrives via env to avoid a pipeline."""
    raw = os.environ.get("PF_OUT", "")
    if not raw.strip():
        print("stdout was empty, so nothing would be injected")
        return 1
    try:
        parsed = json.loads(raw)
    except Exception:
        print("stdout is not JSON; plain text is dropped when the hook exits non-zero")
        return 1
    if not isinstance(parsed, dict):
        print("stdout is JSON but not an object")
        return 1
    block = parsed.get("hookSpecificOutput")
    if not isinstance(block, dict):
        print("no hookSpecificOutput object")
        return 1
    if block.get("hookEventName") != "SessionStart":
        print("hookEventName is %r, expected SessionStart" % block.get("hookEventName"))
        return 1
    context = block.get("additionalContext") or ""
    if not context.strip():
        print("additionalContext is empty, so the pane would start with no protocol")
        return 1
    if ("Agent %s" % agent) not in context:
        print("additionalContext never names Agent %s, so the hook is not branching "
              "per pane" % agent)
        return 1
    # A constant payload listing every agent would satisfy the check above, so also
    # require that this pane's text does not claim to be another pane.
    for other in [p for p in peers.split(",") if p and p != agent]:
        if ("Agent %s" % other) in context:
            print("additionalContext for Agent %s also names Agent %s, so the same text "
                  "is going to more than one pane" % (agent, other))
            return 1
    if project and project not in context:
        print("additionalContext omits the active project %r" % project)
        return 1
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["registration"]:
        sys.exit(registration(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""))
    if sys.argv[1:2] == ["pane1-settings"]:
        sys.exit(pane1_settings(sys.argv[2]))
    if sys.argv[1:2] == ["contract"]:
        sys.exit(contract(sys.argv[2],
                          sys.argv[3] if len(sys.argv) > 3 else "",
                          sys.argv[4] if len(sys.argv) > 4 else ""))
    print("usage: preflight-check.py registration <settings.json> [repo-root] | "
          "contract <agent> [project]")
    sys.exit(2)
