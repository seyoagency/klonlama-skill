#!/usr/bin/env bash
#
# Klonlama skill — one-line installer
# Copies skills/klonlama/SKILL.md into ~/.claude/skills/klonlama/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SCRIPT_DIR}/skills/klonlama/SKILL.md"
TARGET_DIR="${HOME}/.claude/skills/klonlama"
TARGET="${TARGET_DIR}/SKILL.md"

if [ ! -f "${SOURCE}" ]; then
  echo "error: ${SOURCE} not found. Run this script from the repo root."
  exit 1
fi

mkdir -p "${TARGET_DIR}"

if [ -f "${TARGET}" ]; then
  echo "warning: ${TARGET} already exists."
  read -r -p "overwrite? [y/N] " ans
  case "${ans}" in
    [yY]|[yY][eE][sS]) ;;
    *) echo "aborted."; exit 0 ;;
  esac
fi

cp "${SOURCE}" "${TARGET}"
echo "installed: ${TARGET}"
echo ""
echo "next steps:"
echo "  1. open Claude Code (restart if already running)"
echo "  2. type: /klonlama https://example.com/"
echo "  3. or say: 'https://example.com sitesini klonla'"
echo ""
echo "requirements:"
echo "  - node 18+            (node --version)"
echo "  - playwright chromium (npx playwright install chromium)"
echo "  - curl or wget"
