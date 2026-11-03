#!/usr/bin/env bash
# GATEWAY_n=direct|bifrost beside ENGINE_n. Direct must stay byte-identical.
set -uo pipefail
cd "$(dirname "$0")/.."
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s\n' "$1"; FAIL=$((FAIL+1)); }
has() { /usr/bin/grep -qF -- "$2" <<< "$1"; }
source tools/launcher-common.sh

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

echo "--- direct is byte-identical to the pre-gateway command ---"
for eng in claude codex; do
  base=$(engine_cmd 2 $eng m high "" "--append-system-prompt 'X'")
  [ "$(engine_cmd 2 $eng m high "" "--append-system-prompt 'X'" direct)" = "$base" ] \
    && [ "$(engine_cmd 2 $eng m high "" "--append-system-prompt 'X'" "")" = "$base" ] \
    && ok "$eng: direct and empty gateway match the old output" || bad "$eng: direct output changed"
done

echo "--- claude over bifrost ---"
w=$(engine_cmd 2 claude m high "" "--append-system-prompt 'X'" bifrost)
has "$w" "tools/bifrost-claude-settings.json" && ok "worker gets the bifrost settings" || bad "worker missing bifrost settings: $w"
has "$w" "pane1-settings.json" && bad "worker carries pane 1 settings" || ok "worker does not carry pane 1 settings"
o=$(engine_cmd 1 claude m high "" "$ORCH_TOOL_FLAGS" bifrost)
has "$o" "tools/bifrost-claude-settings.json" && has "$o" "pane1-settings.json" \
  && ok "pane 1 merges both settings files" || bad "pane 1 does not merge both: $o"
n=$(grep -o -- '--settings' <<< "$o" | wc -l | tr -d ' ')
# Measured on Claude Code 2.1.316: a repeated --settings replaces the earlier one, so the
# merged argument must come last and carry everything the first one did.
[ "$n" = 2 ] && [ "${o##*--settings}" != "${o%%--settings*}" ] && ok "merged --settings is the last one" || bad "expected 2 --settings, got $n"
tail_arg=${o##*--settings}
has "$tail_arg" "pane1-settings.json" && ok "last --settings includes pane 1's file" || bad "last --settings dropped pane 1's file"
merged=$(jq -s 'reduce .[] as $x ({}; . * $x)' tools/pane1-settings.json tools/bifrost-claude-settings.json 2>&1)
for k in '.permissions' '.apiKeyHelper' '.env.ANTHROPIC_BASE_URL'; do
  jq -e "$k" <<< "$merged" >/dev/null 2>&1 && ok "merged settings keep $k" || bad "merged settings lost $k"
done
has "$(cat tools/bifrost-claude-settings.json)" "auth print-token" && ok "apiKeyHelper fetches a fresh SSO token" || bad "apiKeyHelper is not print-token"
has "$(cat tools/bifrost-claude-settings.json)" "ya29" && bad "a token is stored in the settings file" || ok "no token is stored in the settings file"

echo "--- codex over bifrost ---"
c=$(engine_cmd 3 codex openai/gpt-6.1-sol high "" "" bifrost)
has "$c" " -p bifrost" && ok "codex uses the bifrost profile" || bad "codex missing -p bifrost: $c"
has "$c" "-m 'openai/gpt-6.1-sol'" && ok "codex model id passes through unchanged" || bad "model id altered: $c"
has "$c" "-a never" && ok "codex keeps its existing flags" || bad "codex lost -a never"
has "$c" "BIFROST_CODEX_TOKEN" && bad "a token env is baked into the codex line" || ok "no token is baked into the codex line"

echo "--- unknown gateway is refused ---"
if u=$(engine_cmd 2 claude m high "" "" vpn 2>&1); then bad "unknown gateway accepted: $u"
else ok "unknown gateway refused"; has "$u" "Fix:" && ok "refusal states a remediation" || bad "no remediation: $u"; fi

echo "--- check_bifrost ---"
mkdir -p "$TMP/home"; touch "$TMP/home/bifrost.config.toml"
printf '#!/bin/sh\necho SECRET-TOKEN\nexit 0\n' > "$TMP/good"; printf '#!/bin/sh\necho SECRET-TOKEN\nexit 1\n' > "$TMP/signedout"
chmod +x "$TMP/good" "$TMP/signedout"
export BIFROST_CODEX_PROFILE="$TMP/home/bifrost.config.toml"
BIFROST_BIN="$TMP/good" check_bifrost "claude codex" "bifrost bifrost" >/dev/null 2>&1 && ok "signed-in bifrost passes" || bad "signed-in bifrost refused"
out=$(BIFROST_BIN="$TMP/good" check_bifrost "claude" "bifrost" 2>&1); has "$out" "SECRET-TOKEN" && bad "token leaked into output" || ok "token never reaches output"
out=$(BIFROST_BIN="$TMP/signedout" check_bifrost "claude" "bifrost" 2>&1); rc=$?
[ $rc -ne 0 ] && has "$out" "auth login" && ok "signed-out refused, says how to fix" || bad "signed-out not refused (rc=$rc): $out"
has "$out" "SECRET-TOKEN" && bad "token leaked on failure" || ok "token not leaked on failure"
BIFROST_BIN="$TMP/nope" check_bifrost "claude" "bifrost" >/dev/null 2>&1 && bad "missing binary accepted" || ok "missing binary refused"
BIFROST_BIN="$TMP/good" BIFROST_CODEX_PROFILE="$TMP/none.toml" check_bifrost "codex" "bifrost" >/dev/null 2>&1 \
  && bad "missing codex profile accepted" || ok "missing codex profile refused"
BIFROST_BIN="$TMP/good" BIFROST_CODEX_PROFILE="$TMP/none.toml" check_bifrost "claude" "bifrost" >/dev/null 2>&1 \
  && ok "codex profile not required for claude-only swarm" || bad "claude-only swarm refused over codex profile"
BIFROST_BIN="$TMP/nope" check_bifrost "claude codex" "direct direct" >/dev/null 2>&1 \
  && ok "all-direct swarm never touches bifrost (control)" || bad "all-direct swarm gated on bifrost"

echo "--- launchers persist and replay GATEWAY_n ---"
/usr/bin/grep -q "GATEWAY_1='\$GATEWAY_1'" launch.sh && ok "launch.sh records GATEWAY_n in launch.env" || bad "launch.env does not record GATEWAY_n"
/usr/bin/grep -q 'GATEWAY_\$a' restart-swarm.sh && ok "restart-swarm.sh loads GATEWAY_n" || bad "restart-swarm.sh does not load GATEWAY_n"
/usr/bin/grep -q 'AGENT_GATEWAYS\[\$a\]:-direct' restart-swarm.sh && ok "missing GATEWAY_n defaults to direct on old launch.env" || bad "no direct default"
for f in launch.sh restart-swarm.sh; do
  /usr/bin/grep -q 'check_bifrost' "$f" && ok "$f runs check_bifrost" || bad "$f never runs check_bifrost"
done

echo; echo "  $PASS passed, $FAIL failed"; [ "$FAIL" = 0 ]
