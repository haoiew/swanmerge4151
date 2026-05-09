# SWANMERGE source build and run guide

This guide shows how to build the SWANMERGE executable from this source tree and how to run it on user-provided SWAN MPI output fragments.

The repository does not include a public test case. Replace every placeholder path and case name below with paths and files from your own SWAN run.

---

## 1. Prepare the source directory

Choose a source directory on the Linux system:

```bash
export SWAN_CODE=/path/to/swanmerge4151
cd "$SWAN_CODE"
```

Confirm that the key project files are present:

```bash
test -f swanmain.ftn
test -f Makefile
test -f switch.pl
test -f swanmerge
test -f swanmerge_env.sh
test -f swanmerge_run.sh
grep -n "SWANMERGE_EXE\|make merge\|-merge -mpi" Makefile
grep -n -- "-merge" switch.pl
```

---

## 2. Check oneAPI and build tools

This build recipe uses Intel `mpiifx` for the MPI-enabled merge executable. If your oneAPI installation is in a custom location, set `ONEAPI_SETVARS` before sourcing the environment.

```bash
export ONEAPI_SETVARS=${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}
test -f "$ONEAPI_SETVARS"
source "$ONEAPI_SETVARS" --force

for x in perl make mpiifx mpirun ifx; do
  command -v "$x" || { echo "missing command: $x"; exit 1; }
done
```

If `ONEAPI_SETVARS` does not exist, point it at the real `setvars.sh` on your server:

```bash
export ONEAPI_SETVARS=/path/to/intel/oneapi/setvars.sh
```

---

## 3. Detect METIS, NetCDF, and HDF5

Different systems place libraries in different prefixes. Reuse ABI-compatible existing libraries first; install isolated dependencies only when headers or libraries are missing, or when `ldd` later shows mixed MPI ABIs.

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
export METISROOT=${METISROOT:-$(find_prefix metis.h $SWANMERGE_SEARCH_ROOTS || true)}
export NETCDFROOT=${NETCDFROOT:-$(find_prefix netcdf.h $SWANMERGE_SEARCH_ROOTS || true)}
export HDF5ROOT=${HDF5ROOT:-$(find_prefix hdf5.h $SWANMERGE_SEARCH_ROOTS || true)}

echo "METISROOT=$METISROOT"
echo "NETCDFROOT=$NETCDFROOT"
echo "HDF5ROOT=$HDF5ROOT"
```

Confirm that headers, modules, and libraries exist:

```bash
test -n "$METISROOT"  && test -f "$METISROOT/include/metis.h"
test -n "$NETCDFROOT" && test -f "$NETCDFROOT/include/netcdf.h"
test -f "$NETCDFROOT/include/netcdf.mod"
test -n "$HDF5ROOT"   && test -f "$HDF5ROOT/include/hdf5.h"

export METISLIBDIR=$(find "$METISROOT" $SWANMERGE_SEARCH_ROOTS -type f \( -name 'libmetis.a' -o -name 'libmetis.so*' \) -printf '%h\n' 2>/dev/null | head -n 1)
test -n "$METISLIBDIR" || { echo "MISS: libmetis"; exit 1; }
echo "METISLIBDIR=$METISLIBDIR"
ls -lh "$METISLIBDIR"/libmetis.*
```

If `METISLIBDIR` is found and `ls` shows `libmetis.*`, continue. Install METIS only when the library is truly missing.

---

## 4. Confirm the SWANMERGE source changes

This source tree contains the SWANMERGE merge-only path and the non-structured-grid merge fix. Confirm that the uploaded source matches this project before building:

```bash
cd "$SWAN_CODE"
grep -n "SUBROUTINE SWMERGE\|USE SwanBraggScat\|USE SwanParallel\|BLKNDC = REAL(ipown)\|CORQ%OQI(1).EQ.0" swanmain.ftn
```

Expected key lines include:

```fortran
      USE SwanBraggScat
!METIS      USE SwanParallel
!METIS      BLKNDC = REAL(ipown)
               IF (CORQ%OQI(1).EQ.0) CORQ%OQI(1) = HIOPEN + IRQ
```

---

## 5. Generate `macros.inc`

`macros.inc` defines compilers, flags, and library paths. Generate it from the detected prefixes:

```bash
cd "$SWAN_CODE"
cp -f macros.inc macros.inc.bak.$(date +%F_%H%M%S) 2>/dev/null || true

if ls "$METISLIBDIR"/libGKlib.* >/dev/null 2>&1; then
  GKLIB_FLAG="-lGKlib"
else
  GKLIB_FLAG=""
fi

cat > macros.inc <<EOF
F90_SER = ifx
F90_OMP = ifx
F90_MPI = mpiifx

FLAGS_OPT = -O2
FLAGS_MSC = -W0 -assume byterecl -traceback -diag-disable 8290 -diag-disable 8291 -diag-disable 8293
FLAGS90_MSC = \$(FLAGS_MSC)
FLAGS_DYN = -fPIC

FLAGS_SER =
FLAGS_OMP = -qopenmp
FLAGS_MPI =

METISROOT = $METISROOT
METISLIBDIR = $METISLIBDIR
NETCDFROOT = $NETCDFROOT
HDF5ROOT = $HDF5ROOT

INCS_SER = -I\$(METISROOT)/include -I\$(NETCDFROOT)/include
INCS_OMP = -I\$(METISROOT)/include -I\$(NETCDFROOT)/include
INCS_MPI = -I\$(METISROOT)/include -I\$(NETCDFROOT)/include

LIBS_SER = -L\$(METISLIBDIR) -lmetis $GKLIB_FLAG -L\$(NETCDFROOT)/lib -lnetcdff -lnetcdf -L\$(HDF5ROOT)/lib
LIBS_OMP = -L\$(METISLIBDIR) -lmetis $GKLIB_FLAG -L\$(NETCDFROOT)/lib -lnetcdff -lnetcdf -L\$(HDF5ROOT)/lib
LIBS_MPI = -L\$(METISLIBDIR) -lmetis $GKLIB_FLAG -L\$(NETCDFROOT)/lib -lnetcdff -lnetcdf -L\$(HDF5ROOT)/lib

PART_OBJS = SwanParallel.o
NCF_OBJS = nctablemd.o agioncmd.o swn_outnc.o

OUT = -o
EXTO = o
MAKE = make
RM = rm -f

swch = -unix -metis -netcdf -impi
EOF

grep -E "^(F90_MPI|METISROOT|METISLIBDIR|NETCDFROOT|HDF5ROOT|LIBS_MPI|swch)" macros.inc
```

---

## 6. Build `swanmerge.exe`

```bash
cd "$SWAN_CODE"
source "$ONEAPI_SETVARS" --force
make clobber
make merge
echo "build_exit_code=$?"
```

After compilation:

```bash
test -x "$SWAN_CODE/swanmerge.exe"
grep -n "USE SwanBraggScat\|USE SwanParallel\|BLKNDC = REAL(ipown)" swanmain.f
ldd "$SWAN_CODE/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf|libmetis|libGKlib"
```

If `ldd` shows two incompatible MPI families, install ABI-compatible isolated dependencies and rebuild.

---

## 7. Install a user-level wrapper

The wrapper keeps paths out of shell startup files except for adding `$HOME/bin` to `PATH`.

```bash
cd "$SWAN_CODE"
chmod +x swanmerge swanmerge.exe swanmerge_env.sh swanmerge_run.sh

mkdir -p "$HOME/bin"
ln -sf "$SWAN_CODE/swanmerge.exe" "$HOME/bin/swanmerge.exe"

cat > "$HOME/bin/swanmerge" <<EOF
#!/usr/bin/env bash
set -o pipefail

export ONEAPI_SETVARS="$ONEAPI_SETVARS"
export SWANMERGE_HOME="$SWAN_CODE"
export METISROOT="$METISROOT"
export METISLIBDIR="$METISLIBDIR"
export NCROOT="$NETCDFROOT"
export H5ROOT="$HDF5ROOT"

source "\$SWANMERGE_HOME/swanmerge_env.sh"

if [ -L ./swanmerge.exe ]; then
  rm -f ./swanmerge.exe
fi

exec "\$SWANMERGE_HOME/swanmerge" "\$@"
EOF

chmod +x "$HOME/bin/swanmerge"
grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
source "$HOME/.bashrc"
hash -r

type -a swanmerge
which swanmerge.exe
```

Open a new terminal and confirm:

```bash
source ~/.bashrc
hash -r
type -a swanmerge
which swanmerge.exe
```

---

## 8. Run a merge test with your own case

Prepare a SWAN input file and the corresponding MPI output fragments from your own model run. This repository does not provide or assume any fixed test case name.

Set the variables below for your data:

```bash
export CASE_ID=<your_case_id>
export INPUT_FILE=/path/to/run_${CASE_ID}.swn
export OUTDIR=/path/to/swan/output/fragments
export WORKDIR=/path/to/swanmerge/test/workdir
export BASE=<output_basename_without_fragment_suffix>
export NPROC=<number_of_mpi_fragments>
```

Check that the expected fragments exist:

```bash
cd "$WORKDIR"
ls -1 "$OUTDIR/${BASE}.nc-"* | wc -l
```

Clean old run artifacts and execute:

```bash
cd "$WORKDIR"
rm -f swanmerge.exe INPUT norm_end PRINT PRINT-* Errfile Errfile-* \
      "merge_${CASE_ID}.log" "run_${CASE_ID}.mrg.prt"* "run_${CASE_ID}.mrg.erf"*
rm -f "$OUTDIR/${BASE}.nc"

swanmerge -input "$INPUT_FILE" -mpi "$NPROC" > "merge_${CASE_ID}.log" 2>&1
echo "run_exit_code=$?"
tail -n 80 "merge_${CASE_ID}.log"
ls -lh "$OUTDIR/${BASE}.nc"
```

Expected signs of success are `run_exit_code=0`, an output NetCDF file, and `Normal end of run 1` in the log.

---

## 9. Validate NetCDF values

Creating a NetCDF file is not enough; verify that key variables contain valid values.

```bash
export NCFILE="$OUTDIR/${BASE}.nc"
ls -lh "$NCFILE"

if [ -x "$NETCDFROOT/bin/ncdump" ]; then
  "$NETCDFROOT/bin/ncdump" -h "$NCFILE" | head -n 120
else
  echo "ncdump not found under $NETCDFROOT/bin"
fi
```

Build and run the lightweight C checker:

```bash
cd "$SWAN_CODE"
test -f check_swan_nc.c || { echo "missing check_swan_nc.c"; exit 1; }

icx -O2 -I"$NETCDFROOT/include" check_swan_nc.c \
  -L"$NETCDFROOT/lib" -lnetcdf \
  -o check_swan_nc

LD_LIBRARY_PATH="$NETCDFROOT/lib:$HDF5ROOT/lib:${LD_LIBRARY_PATH:-}" \
  ./check_swan_nc "$NCFILE"
```

At least one important wave variable, such as `hs`, `tps`, or `tm01`, should report `valid > 0`.

Also inspect the merge log:

```bash
grep -niE "error|failed|cannot|inconsistency|iostat|abort" \
  "merge_${CASE_ID}.log" "run_${CASE_ID}.mrg.erf"* 2>/dev/null | head -n 50
```

---

## 10. Common command pattern

After the build and wrapper are installed, the common workflow is:

```bash
cd /path/to/your/swan/workdir
swanmerge -input /path/to/your/run_case.swn -mpi <number_of_mpi_fragments> > merge_case.log 2>&1
echo "exit_code=$?"
tail -n 80 merge_case.log
```

If you see `Too many levels of symbolic links`, remove a stale local symlink and retry:

```bash
rm -f ./swanmerge.exe
hash -r
type -a swanmerge
which swanmerge.exe
```
