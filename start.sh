#!/bin/sh
# Start LidTap and open the GUI. Creates the virtualenv on first run.
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  if command -v uv >/dev/null 2>&1; then
    uv venv -q .venv && uv pip install -q --python .venv/bin/python -r requirements.txt
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m venv .venv && .venv/bin/pip install -q -r requirements.txt
  else
    echo "Error: python3 or uv is required to set up the virtual environment." >&2
    exit 1
  fi
fi
exec .venv/bin/python -m lidtap --open "$@"
