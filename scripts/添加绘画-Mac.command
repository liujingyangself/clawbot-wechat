#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
chmod +x add-drawing.sh 2>/dev/null || true
exec bash add-drawing.sh
