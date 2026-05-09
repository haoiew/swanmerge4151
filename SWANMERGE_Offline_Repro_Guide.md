# SWANMERGE offline dependency build guide

Use this guide only when one of these conditions applies:

1. the target Linux server lacks METIS, HDF5, NetCDF-C, or NetCDF-Fortran;
2. `ldd swanmerge.exe` shows libraries from incompatible MPI families;
3. the server has no internet access, so source archives must be downloaded elsewhere and copied to the server.

If the main build guide already found compatible dependencies and `ldd` does not show mixed MPI ABIs, skip this guide.

---

## 1. Check what is missing

Do not reinstall dependencies by default. Reuse existing ABI-compatible libraries when possible.

```bash
find_prefix () {
  header=$1
  shift
  for root in "$@"; do
    [ -d "$root" ] || continue
    hit=$(find "$root" -type f -path "*/include/$header" 2>/dev/null | head -n 1)
    if [ -n "$hit" ]; then
      dirname "$(dirname "$hit")"
      return 0
    fi
  done
  return 1
}

export SWANMERGE_SEARCH_ROOTS="${SWANMERGE_SEARCH_ROOTS:-$HOME/opt /usr/local /usr /opt}"
export METISROOT=$(find_prefix metis.h $SWANMERGE_SEARCH_ROOTS || true)
export NETCDFROOT=$(find_prefix netcdf.h $SWANMERGE_SEARCH_ROOTS || true)
export HDF5ROOT=$(find_prefix hdf5.h $SWANMERGE_SEARCH_ROOTS || true)

echo "METISROOT=$METISROOT"
echo "NETCDFROOT=$NETCDFROOT"
echo "HDF5ROOT=$HDF5ROOT"

test -n "$METISROOT"  && test -f "$METISROOT/include/metis.h" || echo "MISS: METIS"
test -n "$NETCDFROOT" && test -f "$NETCDFROOT/include/netcdf.h" && test -f "$NETCDFROOT/include/netcdf.mod" || echo "MISS: NetCDF-C/Fortran"
test -n "$HDF5ROOT"   && test -f "$HDF5ROOT/include/hdf5.h" || echo "MISS: HDF5"
```

If `swanmerge.exe` has already been built, check the linked libraries:

```bash
ldd "${SWAN_CODE:-/path/to/swanmerge4151}/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf" || true
```

If two incompatible MPI families appear, rebuild HDF5/NetCDF with the same compiler/MPI stack used for SWANMERGE.

---

## 2. Prepare source archives

When the server has no internet access, download the needed archives on another machine and copy them to the server.

Typical archive names are:

```text
METIS missing: metis-5.1.0.tar.gz
HDF5 missing or MPI ABI conflict: hdf5-1.14.5.tar.gz
NetCDF-C missing or MPI ABI conflict: netcdf-c-4.9.2.tar.gz
NetCDF-Fortran missing or MPI ABI conflict: netcdf-fortran-4.6.1.tar.gz
zlib headers missing: zlib-1.3.1.tar.gz
```

Set a package directory and confirm the files:

```bash
export PKGROOT=/path/to/offline_pkgs
mkdir -p "$PKGROOT"
ls -lh "$PKGROOT"/*.tar.gz
```

Avoid relying on automatically generated archive names such as `v4.9.2.tar.gz`; rename files to the explicit names expected by the commands below.

---

## 3. Set an isolated install prefix

Install into a user-controlled prefix instead of overwriting system libraries:

```bash
export ONEAPI_SETVARS=${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}
source "$ONEAPI_SETVARS" --force

export PREFIX=${PREFIX:-$HOME/opt/swanmerge_intel}
export METISROOT=$PREFIX/metis
export HDF5ROOT=$PREFIX/hdf5
export NETCDFROOT=$PREFIX/netcdf
export SRCROOT=${SRCROOT:-$HOME/src/build_swanmerge_stack}
export PKGROOT=${PKGROOT:-$HOME/src/offline_pkgs}
export JOBS=$(nproc)

mkdir -p "$PREFIX" "$SRCROOT"
cd "$SRCROOT"
```

---

## 4. Install METIS only when needed

First confirm that no usable METIS library exists:

```bash
find $SWANMERGE_SEARCH_ROOTS -type f \( -name 'libmetis.a' -o -name 'libmetis.so*' \) -printf '%h/%f\n' 2>/dev/null | head
```

If the command already finds a compatible library, return to the main build guide and set `METISLIBDIR`. Install METIS only when the library is missing:

```bash
command -v cmake || { echo "MISS: cmake; install cmake first"; exit 1; }

cd "$SRCROOT"
tar -xf "$PKGROOT/metis-5.1.0.tar.gz"
cd metis-5.1.0
make config prefix="$METISROOT" cc=icx
make -j"$JOBS"
make install

test -f "$METISROOT/include/metis.h"
ls "$METISROOT"/lib/libmetis.*
```

Some METIS builds provide `libGKlib`; others do not. The main build guide detects this automatically.

---

## 5. Install HDF5 only when needed

The commands below build serial HDF5 with Intel compilers. This does not make SWANMERGE serial; it only avoids linking NetCDF/HDF5 against an incompatible MPI ABI.

```bash
cd "$SRCROOT"
tar -xf "$PKGROOT/hdf5-1.14.5.tar.gz"
cd hdf5-1.14.5

CC=icx FC=ifx CXX=icpx \
./configure --prefix="$HDF5ROOT" \
  --enable-fortran --enable-hl --enable-shared --disable-static

make -j"$JOBS"
make install

test -f "$HDF5ROOT/include/hdf5.h"
ldd "$HDF5ROOT/lib/libhdf5.so" | grep libmpi || echo "OK: HDF5 is not linked to MPI"
```

If zlib is missing, install it into the same isolated prefix:

```bash
cd "$SRCROOT"
tar -xf "$PKGROOT/zlib-1.3.1.tar.gz"
cd zlib-1.3.1
CC=icx ./configure --prefix="$PREFIX/zlib"
make -j"$JOBS"
make install
```

Then rerun the HDF5 configuration with:

```bash
--with-zlib="$PREFIX/zlib"
```

---

## 6. Install NetCDF-C only when needed

Disable DAP and parallel4 to reduce offline dependencies and avoid MPI ABI mixing:

```bash
cd "$SRCROOT"
tar -xf "$PKGROOT/netcdf-c-4.9.2.tar.gz"
cd netcdf-c-4.9.2

export CPPFLAGS="-I$HDF5ROOT/include"
export LDFLAGS="-L$HDF5ROOT/lib"
export LD_LIBRARY_PATH="$HDF5ROOT/lib:${LD_LIBRARY_PATH:-}"

CC=icx ./configure --prefix="$NETCDFROOT" \
  --enable-netcdf-4 --disable-dap --disable-parallel4 \
  --enable-shared --disable-static

make -j"$JOBS"
make install

test -f "$NETCDFROOT/include/netcdf.h"
ldd "$NETCDFROOT/lib/libnetcdf.so" | grep libmpi || echo "OK: NetCDF-C is not linked to MPI"
```

---

## 7. Install NetCDF-Fortran only when needed

SWANMERGE needs `netcdf.mod` and `libnetcdff.so`:

```bash
cd "$SRCROOT"
tar -xf "$PKGROOT/netcdf-fortran-4.6.1.tar.gz"
cd netcdf-fortran-4.6.1

export CPPFLAGS="-I$NETCDFROOT/include -I$HDF5ROOT/include"
export LDFLAGS="-L$NETCDFROOT/lib -L$HDF5ROOT/lib"
export LD_LIBRARY_PATH="$NETCDFROOT/lib:$HDF5ROOT/lib:${LD_LIBRARY_PATH:-}"

FC=ifx ./configure --prefix="$NETCDFROOT" --enable-shared --disable-static
make -j"$JOBS"
make install

test -f "$NETCDFROOT/include/netcdf.mod"
ldd "$NETCDFROOT/lib/libnetcdff.so" | egrep -i "libmpi|libnetcdf" || true
```

`libnetcdff.so` should link to `libnetcdf.so`, but it should not introduce an incompatible MPI library.

---

## 8. Rebuild SWANMERGE with the isolated dependencies

```bash
export SWAN_CODE=/path/to/swanmerge4151
cd "$SWAN_CODE"
test -f Makefile
test -f switch.pl

export METISROOT=${METISROOT:-$HOME/opt/swanmerge_intel/metis}
export HDF5ROOT=${HDF5ROOT:-$HOME/opt/swanmerge_intel/hdf5}
export NETCDFROOT=${NETCDFROOT:-$HOME/opt/swanmerge_intel/netcdf}

source "$ONEAPI_SETVARS" --force
```

Then return to the main build guide and continue from the `macros.inc` generation step.

---

## 9. Final ABI check

```bash
ldd "$SWAN_CODE/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf"
```

Acceptable results should show a single MPI family, for example Intel oneAPI MPI plus ABI-compatible NetCDF/HDF5 libraries.

If both Intel MPI and OpenMPI libraries appear, inspect `LD_LIBRARY_PATH`, `macros.inc`, and `ldd` output for `libnetcdf.so` and `libhdf5.so`, then rebuild against a consistent stack.

---

## 10. Key point

`BLKNDC = REAL(ipown)` addresses the non-structured-grid merge issue where merged NetCDF values can become all missing values. Isolated HDF5/NetCDF builds address missing dependency or MPI ABI issues. They solve different problems and should not be treated as substitutes for each other.
