#!/usr/bin/env bash
# Launcher preflight for the SessionStart hook. Source this, then call:
#   preflight_hook <settings.json> <repo-root> <swarm-id> <agent>...
# Returns 0 only when the hook is demonstrably healthy. Callers abort the launch.
#
# Scope of the guarantee, deliberately narrow: it certifies the hook at the instant of
# launch, for panes started through a launcher. It cannot gate `claude` run by hand, and
# /clear has no launcher in front of it, so that path is never gated.
#
# Call it from an `if`, which suspends errexit inside the function, so every assertion
# returns explicitly rather than relying on set -e.

PF_BUDGET_S=1.5

_pf_fail() { # <file> <assertion> <detail> <remediation>
  printf 'PREFLIGHT REFUSED: %s\n  assertion: %s\n  %s\n  Fix: %s\n' \
    "$1" "$2" "$3" "$4" >&2
}

preflight_hook() {
  local settings=$1 root=$2 swarm=$3; shift 3
  local here reg hook timeout project out rc dur detail checker
  # ${BASH_SOURCE[0]} is empty when this file is sourced by a non-bash shell, which
  # would otherwise resolve the helper to the wrong directory.
  here="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" 2>/dev/null && pwd)" || here=""
  checker="$here/preflight-check.py"

  if [ ! -x "$checker" ]; then
    _pf_fail "${checker:-<unresolved>}" "the preflight's own checker is present" \
      "the preflight cannot run, so it must not report a healthy hook" \
      "restore tools/preflight-check.py next to tools/preflight-hook.sh"
    return 1
  fi

  reg=$("$checker" registration "$settings" "$root")
  if [ -z "$reg" ]; then
    _pf_fail "$settings" "the registration lookup produced a result" \
      "the checker returned nothing when asked for the registered hook" \
      "run tools/preflight-check.py registration $settings by hand to see why"
    return 1
  fi
  if [ "${reg%%$'\t'*}" = "ERR" ]; then
    _pf_fail "$settings" "a SessionStart command hook is registered" "${reg#*$'\t'}" \
      "add a SessionStart command hook to $settings pointing at .claude/hooks/startup.sh"
    return 1
  fi
  hook=${reg%%$'\t'*}
  timeout=${reg#*$'\t'}

  if [ ! -f "$hook" ]; then
    _pf_fail "$hook" "the registered hook file exists" \
      "$settings registers this path and nothing is there" \
      "create $hook, or correct the path in $settings"
    return 1
  fi
  if [ ! -x "$hook" ]; then
    _pf_fail "$hook" "the registered hook is executable" "the file exists but is not executable" \
      "chmod +x $hook"
    return 1
  fi

  project=""
  if [ -r "$root/swarms/$swarm/ACTIVE_PROJECT" ]; then
    project=$(cat "$root/swarms/$swarm/ACTIVE_PROJECT")
  fi
  if [ -z "$project" ]; then
    _pf_fail "$root/swarms/$swarm/ACTIVE_PROJECT" "the active project is resolved before panes start" \
      "no readable ACTIVE_PROJECT, so panes would start without project context" \
      "write swarms/$swarm/ACTIVE_PROJECT before calling the preflight"
    return 1
  fi

  local agent src t0 t1 peers budget
  peers=$(printf '%s,' "$@"); peers=${peers%,}

  # F3: the hook's own configured timeout can be tighter than our budget. Claude kills
  # the hook at that timeout and continues WITHOUT context, so gate on whichever is
  # smaller rather than on our constant alone.
  budget=$(python3 -c "print(min($PF_BUDGET_S, $timeout * 0.5))")
  for agent in "$@"; do
    # /clear re-fires the hook and is the branch a launcher cannot gate later, so both
    # sources are exercised here where they still can be.
    for src in startup clear; do
      t0=$(python3 -c 'import time;print(time.time())')
      out=$(AGENT_NUMBER="$agent" SWARM_ID="$swarm" "$hook" \
            <<< "{\"session_id\":\"preflight\",\"source\":\"$src\",\"cwd\":\"$root\"}" 2>/dev/null)
      rc=$?
      t1=$(python3 -c 'import time;print(time.time())')

      if [ "$rc" -ne 0 ]; then
        _pf_fail "$hook" "exit status is 0 (agent $agent, source $src)" \
          "the hook exited $rc; JSON still injects on a non-zero exit, so this would have looked healthy at runtime" \
          "make the hook exit 0 on every path, then re-run the launch"
        return 1
      fi
      local dfile; dfile=$(mktemp)
      if ! PF_OUT="$out" "$checker" contract "$agent" "$project" "$peers" > "$dfile" 2>&1; then
        detail=$(cat "$dfile"); rm -f "$dfile"
        _pf_fail "$hook" "output contract (agent $agent, source $src)" "$detail" \
          "the hook must print {\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"...\"}} naming the agent and the project"
        return 1
      fi
      rm -f "$dfile"
      dur=$(python3 -c "print(round($t1-$t0,3))")
      if ! python3 -c "import sys; sys.exit(0 if $dur < $budget else 1)"; then
        _pf_fail "$hook" "runs inside the budget (agent $agent, source $src)" \
          "took ${dur}s against a ${budget}s budget (the smaller of our ${PF_BUDGET_S}s and half the hook's configured ${timeout}s timeout); restart-swarm soft mode waits only KICK_WAIT=3 before the kick" \
          "make the hook faster, or raise KICK_WAIT and the hook timeout deliberately"
        return 1
      fi
    done
  done

  # Detection, not a gate. The hook can still be edited after this point; recording what
  # was verified lets someone compare later. Nothing enforces the comparison, and the
  # write is best effort.
  if [ -d "$root/swarms/$swarm" ]; then
    printf '%s  %s\n' "$(shasum -a 256 "$hook" | cut -d' ' -f1)" "$hook" \
      > "$root/swarms/$swarm/hook.sha256"
    # Record only, deliberately no assertion: version pinning is not approved. Swarm 218
    # ran 2.1.276 while 220 ran 2.1.278 because the claude symlink moved between the two
    # launches, and the paste threshold behind the orphaned sends is version dependent.
    # This lets a future orphan be correlated with the build that produced it.
    {
      printf 'recorded_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'claude_path=%s\n' "$(command -v claude 2>/dev/null || echo unresolved)"
      printf 'claude_realpath=%s\n' \
        "$(python3 -c 'import os,shutil,sys; p=shutil.which("claude"); print(os.path.realpath(p) if p else "unresolved")' 2>/dev/null || echo unresolved)"
      printf 'claude_version=%s\n' "$(claude --version 2>/dev/null | head -1 || echo unresolved)"
    } > "$root/swarms/$swarm/claude-build.txt"
  fi
  return 0
}
