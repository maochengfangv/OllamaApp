#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="${PYTHON:-python3}"
TOOL="$SCRIPT_DIR/linkmap_macho_diff.py"

LINKMAP_A=""
LINKMAP_B=""
MACHO_A=""
MACHO_B=""
MAIN_MODULE="OllamaApp"
ARCH="arm64"
TOP="50"
JSON_OUT=""
ALL_SYMBOLS="0"

usage() {
  cat <<'EOF'
Usage:
  analyze_linkmap_macho_size_diff.sh \
    --linkmap-a <A-LinkMap.txt> --linkmap-b <B-LinkMap.txt> \
    --macho-a <A-MachO> --macho-b <B-MachO> \
    [--main-module <TargetName>] [--arch arm64|x86_64] [--top <N>] [--json-out <file>] [--all-symbols]

Examples:
  ./analyze_linkmap_macho_size_diff.sh \
    --linkmap-a /path/A-LinkMap.txt --linkmap-b /path/B-LinkMap.txt \
    --macho-a /path/A.app/OllamaApp --macho-b /path/B.app/OllamaApp \
    --main-module OllamaApp --arch arm64 --top 50 --json-out /tmp/size-diff.json
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --linkmap-a) LINKMAP_A="${2:-}"; shift 2;;
    --linkmap-b) LINKMAP_B="${2:-}"; shift 2;;
    --macho-a) MACHO_A="${2:-}"; shift 2;;
    --macho-b) MACHO_B="${2:-}"; shift 2;;
    --main-module) MAIN_MODULE="${2:-}"; shift 2;;
    --arch) ARCH="${2:-}"; shift 2;;
    --top) TOP="${2:-}"; shift 2;;
    --json-out) JSON_OUT="${2:-}"; shift 2;;
    --all-symbols) ALL_SYMBOLS="1"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$LINKMAP_A" || -z "$LINKMAP_B" || -z "$MACHO_A" || -z "$MACHO_B" ]]; then
  echo "Missing required args." >&2
  usage
  exit 2
fi

if [[ ! -f "$TOOL" ]]; then
  echo "Tool not found: $TOOL" >&2
  exit 2
fi

if ! command -v "$PY" >/dev/null 2>&1; then
  echo "python3 not found. Set PYTHON=/path/to/python3 and retry." >&2
  exit 2
fi

ARGS=(
  "--linkmap-a" "$LINKMAP_A"
  "--linkmap-b" "$LINKMAP_B"
  "--macho-a" "$MACHO_A"
  "--macho-b" "$MACHO_B"
  "--main-module" "$MAIN_MODULE"
  "--arch" "$ARCH"
  "--top" "$TOP"
)

if [[ -n "$JSON_OUT" ]]; then
  ARGS+=("--json-out" "$JSON_OUT")
fi

if [[ "$ALL_SYMBOLS" == "1" ]]; then
  ARGS+=("--all-symbols")
fi

"$PY" "$TOOL" "${ARGS[@]}"
