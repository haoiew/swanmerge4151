#!/usr/bin/env bash
set -o pipefail

if [ "${SWMERGE_DEBUG:-0}" = "1" ]; then
  set -x
fi

if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") -input run_xxxx.swn [-mpi n]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -f "${SCRIPT_DIR}/swanmerge_env.sh" ]; then
  if ! source "${SCRIPT_DIR}/swanmerge_env.sh"; then
    echo "Failed to load SWANMERGE environment from ${SCRIPT_DIR}/swanmerge_env.sh" >&2
    exit 20
  fi
else
  SWANMERGE_HOME=${SWANMERGE_HOME:-${SCRIPT_DIR}}
  if ! source "${SWANMERGE_HOME}/swanmerge_env.sh"; then
    echo "Failed to load SWANMERGE environment from ${SWANMERGE_HOME}/swanmerge_env.sh" >&2
    exit 20
  fi
fi

if [ ! -x "$SWANMERGE_SCRIPT" ]; then
  echo "SWANMERGE script is not executable: $SWANMERGE_SCRIPT" >&2
  exit 3
fi

if [ -L ./swanmerge.exe ]; then
  rm -f ./swanmerge.exe
fi

exec "$SWANMERGE_SCRIPT" "$@"
