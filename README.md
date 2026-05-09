# SWANMERGE 41.51

[中文说明](README.zh-CN.md)

SWANMERGE is a SWAN 41.51 merge-only extension branch. It focuses on building and running `swanmerge.exe`, a standalone merge executable for SWAN MPI NetCDF output fragments.

This project is intended for post-processing SWAN MPI outputs. It does not use the full SWAN wave computation workflow; it keeps the SWAN 41.51 source layout and adds the build/runtime support needed for the merge path.

## Intended use

Use this project when all of the following are true:

- You already ran SWAN in MPI mode and have per-rank output fragments such as `case.nc-001`, `case.nc-002`, and so on.
- You need a standalone command to merge those fragments into one NetCDF file without rerunning the full wave simulation.
- Your case uses SWAN output and grid settings compatible with the original SWAN merge path.
- You can build SWAN from source on a Linux system with Intel oneAPI, MPI, METIS, HDF5, and NetCDF.

The most important practical target is non-structured-grid SWAN NetCDF merging where the merged file may otherwise be created but contain only missing values. This tree includes the `SWMERGE` path and the `BLKNDC = REAL(ipown)` merge fix used for that case.

## Not intended for

This repository does not provide a complete public SWAN benchmark case. It does not include bathymetry, wind, boundary spectra, typhoon cases, or any private model outputs. Users must test with their own SWAN input file and their own MPI output fragments.

This project is also not intended to:

- replace a full SWAN model build for wave simulation;
- change SWAN physics or calibration defaults;
- provide general SWAN model setup guidance;
- provide prebuilt binaries for every compiler/MPI stack;
- guarantee that a merged file is scientifically valid without checking the original model setup and outputs.

## What changed from SWAN 41.51

The project keeps the original SWAN source files and license headers. This branch adds or changes the following merge-related pieces:

- `Makefile`: adds `make merge` and `swanmerge.exe` targets.
- `switch.pl`: adds the `-merge` switch to activate merge-only source sections.
- `swanmain.ftn`: includes the `SWMERGE` path and merge-specific fixes, including the non-structured-grid ownership field assignment used by the merge workflow.
- `swanmerge`, `swanmerge_run.sh`, `swanmerge_env.sh`: runtime wrappers for loading dependencies and running merge jobs.
- `check_swan_nc.c`: a lightweight NetCDF value checker for merged output.
- `SWANMERGE_SourceBuild_Run_Guide.md`: source build, install, run, and validation workflow. See [Chinese version](SWANMERGE_SourceBuild_Run_Guide.zh-CN.md).
- `SWANMERGE_Offline_Repro_Guide.md`: offline dependency build workflow for servers without suitable libraries. See [Chinese version](SWANMERGE_Offline_Repro_Guide.zh-CN.md).

## Quick start

Build on Linux from the repository root:

```bash
export SWAN_CODE=/path/to/swanmerge4151
cd "$SWAN_CODE"
```

Follow the full build workflow in [SWANMERGE_SourceBuild_Run_Guide.md](SWANMERGE_SourceBuild_Run_Guide.md). The short version is:

```bash
export ONEAPI_SETVARS=${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}
source "$ONEAPI_SETVARS" --force

# Set these to the dependency prefixes on your machine.
export METISROOT=/path/to/metis
export METISLIBDIR=/path/to/metis/lib
export NETCDFROOT=/path/to/netcdf
export HDF5ROOT=/path/to/hdf5

# Generate macros.inc as shown in the build guide, then:
make clobber
make merge
```

Run with your own SWAN case from the run directory:

```bash
cd /path/to/your/swan/workdir
test -f run_case.swn
swanmerge -input run_case.swn -mpi <number_of_mpi_fragments> > merge_case.log 2>&1
```

The current directory matters. `swanmerge` copies `run_case.swn` to `INPUT` in the current directory and writes `PRINT*`, `Errfile*`, `norm_end`, and merge logs there. The SWAN MPI output fragments must exist at the paths expected by `run_case.swn`; if those paths are relative, they are resolved from this run directory.

Then validate the merged NetCDF with `ncdump` and `check_swan_nc.c` as shown in the build guide.

## Dependencies

Typical build dependencies are:

- Perl and Make
- Intel oneAPI `ifx`, `mpiifx`, and Intel MPI runtime
- METIS
- HDF5
- NetCDF-C
- NetCDF-Fortran
- C compiler for `check_swan_nc.c`

The wrapper scripts do not assume a fixed server path. Set `ONEAPI_SETVARS`, `SWANMERGE_HOME`, `NCROOT`, `H5ROOT`, `METISROOT`, `METISLIBDIR`, or `SWANMERGE_SEARCH_ROOTS` for your machine.

## Testing with your data

Before publishing or using merged results, check three things:

1. `swanmerge` exits with status `0` and logs `Normal end of run`.
2. The expected merged `.nc` file exists.
3. Important variables such as `hs`, `tps`, or `tm01` contain valid values, not only missing values.

The included `check_swan_nc.c` helper reads selected NetCDF variables and reports `valid/total/min/max`.

## License and upstream status

SWANMERGE is distributed under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE).

The original SWAN model is developed by Delft University of Technology and is distributed under the GNU GPL. This repository preserves the original SWAN copyright and license headers.

Users should cite the original SWAN model and papers when using this software in academic or operational work. See [CITATION.cff](CITATION.cff) and [NOTICE](NOTICE).

## Citation

The core SWAN reference is:

Booij, N., Ris, R. C., and Holthuijsen, L. H. (1999). A third-generation wave model for coastal regions: 1. Model description and validation. Journal of Geophysical Research: Oceans, 104(C4), 7649-7666. https://doi.org/10.1029/98JC02622

Also cite this repository when the SWANMERGE merge-specific changes are material to your workflow.
