#!/bin/bash
# Parse-checks every GDScript file and prints errors with their location.
cd "$(dirname "$0")/.."
for f in $(find scripts tools -name "*.gd" | sort); do
  out=$(timeout 60 godot --headless --path . --check-only --script "res://$f" 2>&1 | grep -A1 -E "Parse Error" | grep -vE "^--$")
  if [ -n "$out" ]; then echo "== $f"; echo "$out" | head -${1:-12}; fi
done
