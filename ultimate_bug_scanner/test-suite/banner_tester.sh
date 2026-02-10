#!/usr/bin/env bash
set -euo pipefail
modules=(
  "modules/ubs-js.sh:JavaScript/TypeScript"
  "modules/ubs-python.sh:Python"
  "modules/ubs-cpp.sh:C/C++"
  "modules/ubs-rust.sh:Rust"
  "modules/ubs-golang.sh:Go"
  "modules/ubs-java.sh:Java"
  "modules/ubs-ruby.sh:Ruby"
  "modules/ubs-swift.sh:Swift"
)
for entry in "${modules[@]}"; do
  file="${entry%%:*}"
  label="${entry##*:}"
  printf '\n===== %s =====\n\n' "$label"
  awk '
    /^[[:space:]]*cat <<'\''BANNER'\''$/ {capture=1; next}
    capture && /^BANNER$/ {exit}
    capture {print}
  ' "$file"
done
