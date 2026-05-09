#!/usr/bin/env bash

# Runtime environment for SWANMERGE.
# Override these before sourcing when a server uses different paths:
#   ONEAPI_SETVARS=/path/to/setvars.sh
#   SWANMERGE_HOME=/path/to/swan/source
#   NCROOT=/path/to/netcdf H5ROOT=/path/to/hdf5 METISROOT=/path/to/metis
#   SWANMERGE_SEARCH_ROOTS="/opt /usr/local $HOME/opt"

_swanmerge_missing=0

_swanmerge_error() {
  echo "[ERROR] $1" >&2
  _swanmerge_missing=1
}

swanmerge_find_prefix() {
  header_name=$1
  shift
  for root in "$@"; do
    [ -d "$root" ] || continue
    found=$(find "$root" -type f -path "*/include/${header_name}" 2>/dev/null | head -n 1)
    if [ -n "$found" ]; then
      dirname "$(dirname "$found")"
      return 0
    fi
  done
  return 1
}

swanmerge_find_libdir() {
  lib_pattern=$1
  shift
  for root in "$@"; do
    [ -d "$root" ] || continue
    found=$(find "$root" -type f -name "$lib_pattern" 2>/dev/null | head -n 1)
    if [ -n "$found" ]; then
      dirname "$found"
      return 0
    fi
  done
  return 1
}

SWANMERGE_ENV_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ONEAPI_SETVARS=${ONEAPI_SETVARS:-${ONEAPI_ROOT:-/opt/intel/oneapi}/setvars.sh}
SWANMERGE_SEARCH_ROOTS=${SWANMERGE_SEARCH_ROOTS:-"$HOME/opt /usr/local /usr /opt"}
if [ -f "$ONEAPI_SETVARS" ]; then
  case $- in
    *u*) _swanmerge_had_nounset=1 ;;
    *) _swanmerge_had_nounset=0 ;;
  esac
  set +u
  # Intel setvars.sh may touch unset variables; source it with nounset disabled.
  if ! source "$ONEAPI_SETVARS" --force >/dev/null 2>&1; then
    echo "[WARN] setvars.sh returned non-zero; continuing with current environment" >&2
  fi
  [ "$_swanmerge_had_nounset" = 1 ] && set -u
else
  echo "[WARN] oneAPI setvars.sh not found: $ONEAPI_SETVARS" >&2
fi

export SWANMERGE_HOME=${SWANMERGE_HOME:-$SWANMERGE_ENV_DIR}
export SWANMERGE_SCRIPT=${SWANMERGE_SCRIPT:-${SWANMERGE_HOME}/swanmerge}
export SWANMERGE_BINARY=${SWANMERGE_BINARY:-${SWANMERGE_HOME}/swanmerge.exe}

if [ -z "${NCROOT:-}" ] || [ ! -f "${NCROOT:-}/include/netcdf.h" ]; then
  NCROOT=$(swanmerge_find_prefix netcdf.h $SWANMERGE_SEARCH_ROOTS || true)
fi
if [ -z "${H5ROOT:-}" ] || [ ! -f "${H5ROOT:-}/include/hdf5.h" ]; then
  H5ROOT=$(swanmerge_find_prefix hdf5.h $SWANMERGE_SEARCH_ROOTS || true)
fi
if [ -z "${METISROOT:-}" ] || [ ! -f "${METISROOT:-}/include/metis.h" ]; then
  METISROOT=$(swanmerge_find_prefix metis.h $SWANMERGE_SEARCH_ROOTS || true)
fi
if [ -z "${METISLIBDIR:-}" ] || { [ ! -f "${METISLIBDIR:-}/libmetis.a" ] && ! ls "${METISLIBDIR:-}"/libmetis.so* >/dev/null 2>&1; }; then
  METISLIBDIR=$(swanmerge_find_libdir libmetis.a "${METISROOT:-}" $SWANMERGE_SEARCH_ROOTS || true)
fi
if [ -z "${METISLIBDIR:-}" ]; then
  METISLIBDIR=$(swanmerge_find_libdir 'libmetis.so*' "${METISROOT:-}" $SWANMERGE_SEARCH_ROOTS || true)
fi

export NCROOT H5ROOT METISROOT METISLIBDIR

[ -d "$SWANMERGE_HOME" ] || _swanmerge_error "SWANMERGE_HOME not found: $SWANMERGE_HOME"
[ -x "$SWANMERGE_SCRIPT" ] || _swanmerge_error "SWANMERGE script is not executable: $SWANMERGE_SCRIPT"
[ -x "$SWANMERGE_BINARY" ] || _swanmerge_error "SWANMERGE binary is not executable: $SWANMERGE_BINARY"
[ -n "${NCROOT:-}" ] && [ -d "${NCROOT}/lib" ] || _swanmerge_error "NetCDF root was not found. Set NCROOT or install NetCDF first."
[ -n "${H5ROOT:-}" ] && [ -d "${H5ROOT}/lib" ] || _swanmerge_error "HDF5 root was not found. Set H5ROOT or install HDF5 first."
[ -n "${METISROOT:-}" ] && [ -f "${METISROOT}/include/metis.h" ] || _swanmerge_error "METIS include root was not found. Set METISROOT or install METIS first."
[ -n "${METISLIBDIR:-}" ] && [ -d "${METISLIBDIR}" ] || _swanmerge_error "METIS library directory was not found. Set METISLIBDIR or install METIS first."

if [ "$_swanmerge_missing" -ne 0 ]; then
  return 20 2>/dev/null || exit 20
fi

ld_paths=""
for d in \
  "${I_MPI_ROOT:-}/lib" \
  "${CMPLR_ROOT:-}/lib" \
  "${NCROOT:-}/lib" \
  "${H5ROOT:-}/lib" \
  "${METISROOT:-}/lib" \
  "${METISLIBDIR:-}"; do
  [ -d "$d" ] || continue
  if [ -z "$ld_paths" ]; then
    ld_paths=$d
  else
    ld_paths=${ld_paths}:$d
  fi
done

if [ -n "$ld_paths" ]; then
  export LD_LIBRARY_PATH=${ld_paths}:${LD_LIBRARY_PATH:-}
fi

export PATH=${SWANMERGE_HOME}:$HOME/bin:$PATH
