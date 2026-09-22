#!/usr/bin/env bash
# Fixture builders shared by preflight_test.sh. Not a *_test.sh, so run.sh ignores it.
# Builds a sandbox: <root>/swarms/<sid>/ACTIVE_PROJECT, a settings.json, and a hook.
mkfix() { # $1=variant  -> echoes the sandbox root
  local v=$1 root hook
  root=$(mktemp -d)
  mkdir -p "$root/swarms/220" "$root/hooks" "$root/tools"
  printf 'demo' > "$root/swarms/220/ACTIVE_PROJECT"
  # pane 1 launches with --settings this file, and the gate refuses without it, so every
  # fixture needs a valid one or each failure would be attributed to the wrong cause.
  cp "$REPO/tools/pane1-settings.json" "$root/tools/pane1-settings.json"
  hook="$root/hooks/startup.sh"
  case $v in
    good)      cp "$REPO/.claude/hooks/startup.sh" "$hook"
               cp "$REPO/.claude/hooks/startup.py" "$root/hooks/startup.py" ;;
    missing)   : ;;                                   # no hook written at all
    notexec)   printf '#!/usr/bin/env bash\ntrue\n' > "$hook"; chmod -x "$hook" ;;
    notjson)   printf '#!/usr/bin/env bash\ncat >/dev/null\necho "You are Agent $AGENT_NUMBER"\n' > "$hook" ;;
    wrongevent) printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"Nope\\",\\"additionalContext\\":\\"You are Agent $AGENT_NUMBER\\"}}"\n' > "$hook" ;;
    emptyctx)  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"\\"}}"\n' > "$hook" ;;
    nobranch)  printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"protocol loaded for demo\\"}}"\n' > "$hook" ;;
    slow)      printf '#!/usr/bin/env bash\ncat >/dev/null\nsleep 3\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"You are Agent $AGENT_NUMBER demo\\"}}"\n' > "$hook" ;;
    exit1)     printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"You are Agent $AGENT_NUMBER demo\\"}}"\nexit 1\n' > "$hook" ;;
    noproject) cp "$REPO/.claude/hooks/startup.sh" "$hook"
               cp "$REPO/.claude/hooks/startup.py" "$root/hooks/startup.py"
               rm -f "$root/swarms/220/ACTIVE_PROJECT" ;;
    projdir)   cp "$REPO/.claude/hooks/startup.sh" "$hook"
               cp "$REPO/.claude/hooks/startup.py" "$root/hooks/startup.py" ;;
    allagents) printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"Agent 1 Agent 2 Agent 3 Agent 4 demo\\"}}"\n' > "$hook" ;;
    clearonly) printf '#!/usr/bin/env bash\np=$(cat)\ncase "$p" in *clear*) exit 9 ;; esac\nprintf %%s "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"SessionStart\\",\\"additionalContext\\":\\"You are Agent $AGENT_NUMBER demo\\"}}"\n' > "$hook" ;;
  esac
  [ -f "$hook" ] && [ "$v" != notexec ] && chmod +x "$hook"
  if [ "$v" = unregistered ]; then printf '{ "hooks": {} }\n' > "$root/settings.json"
  elif [ "$v" = projdir ]; then
    # exactly the form .claude/settings.json uses in production
    printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "\\"$CLAUDE_PROJECT_DIR\\"/hooks/startup.sh", "timeout": 10 } ] } ] } }\n' > "$root/settings.json"
  else printf '{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "%s", "timeout": 10 } ] } ] } }\n' "$hook" > "$root/settings.json"; fi
  echo "$root"
}
