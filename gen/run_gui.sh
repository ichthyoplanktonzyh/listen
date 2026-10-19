#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

if [ -f ".venv/bin/python" ]; then
    PYTHON=".venv/bin/python"
elif command -v python3 &> /dev/null; then
    PYTHON="python3"
elif command -v python &> /dev/null; then
    PYTHON="python"
else
    echo "Error: Python interpreter not found."
    exit 1
fi

export PYTHONPATH="src:${PYTHONPATH}"
exec "$PYTHON" -m listen_gen gui "$@"
