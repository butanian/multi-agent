#!/usr/bin/env bash
# SessionStart hook. See startup.py. Kept as a thin exec so the payload on stdin passes
# straight through and nothing here needs a shell temp file.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/startup.py"
