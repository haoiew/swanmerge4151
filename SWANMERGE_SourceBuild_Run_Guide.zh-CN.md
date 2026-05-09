# SWANMERGE 源码构建与运行指南

[English version](SWANMERGE_SourceBuild_Run_Guide.md)

本指南说明如何从本源码树构建 SWANMERGE 可执行程序，并如何用用户自己提供的 SWAN MPI 输出分片运行合并。

本仓库不包含公开测试案例。下面所有占位路径和案例名都需要替换为你自己的 SWAN 运行目录、输入文件和输出分片。

---

## 1. 准备源码目录

在 Linux 系统上选择源码目录：

```bash
export SWAN_CODE=/path/to/swanmerge4151
cd "$SWAN_CODE"
```

确认关键项目文件存在：

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

## 2. 检查 oneAPI 和构建工具

本构建方案使用 Intel `mpiifx` 编译 MPI 版合并程序。如果你的 oneAPI 安装在自定义位置，请先设置 `ONEAPI_SETVARS`。

```bash
export ONEAPI_SETVARS=${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}
test -f "$ONEAPI_SETVARS"
source "$ONEAPI_SETVARS" --force

for x in perl make mpiifx mpirun ifx; do
  command -v "$x" || { echo "missing command: $x"; exit 1; }
done
```

如果 `ONEAPI_SETVARS` 不存在，请改成当前服务器上的真实路径：

```bash
export ONEAPI_SETVARS=/path/to/intel/oneapi/setvars.sh
```

---

## 3. 探测 METIS、NetCDF 和 HDF5

不同服务器的依赖库位置不一致。优先复用 ABI 兼容的现有库；只有缺少头文件/库文件，或者后续 `ldd` 显示 MPI ABI 混用时，才安装隔离依赖。

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

确认头文件、Fortran module 和库文件存在：

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

如果已经找到 `METISLIBDIR` 且能看到 `libmetis.*`，继续下一步。只有真正缺少库文件时再安装 METIS。

---

## 4. 确认 SWANMERGE 源码修复

本源码树包含 SWANMERGE 的仅合并路径和非结构网格合并修复。构建前先确认上传源码与本项目一致：

```bash
cd "$SWAN_CODE"
grep -n "SUBROUTINE SWMERGE\|USE SwanBraggScat\|USE SwanParallel\|BLKNDC = REAL(ipown)\|CORQ%OQI(1).EQ.0" swanmain.ftn
```

预期关键行包括：

```fortran
      USE SwanBraggScat
!METIS      USE SwanParallel
!METIS      BLKNDC = REAL(ipown)
               IF (CORQ%OQI(1).EQ.0) CORQ%OQI(1) = HIOPEN + IRQ
```

---

## 5. 生成 `macros.inc`

`macros.inc` 定义编译器、编译选项和库路径。用探测到的依赖前缀生成它：

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

## 6. 编译 `swanmerge.exe`

```bash
cd "$SWAN_CODE"
source "$ONEAPI_SETVARS" --force
make clobber
make merge
echo "build_exit_code=$?"
```

编译后检查：

```bash
test -x "$SWAN_CODE/swanmerge.exe"
grep -n "USE SwanBraggScat\|USE SwanParallel\|BLKNDC = REAL(ipown)" swanmain.f
ldd "$SWAN_CODE/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf|libmetis|libGKlib"
```

如果 `ldd` 显示两个不兼容的 MPI 家族，请安装 ABI 一致的隔离依赖后重新编译。

---

## 7. 安装用户级包装器

包装器只把 `$HOME/bin` 加入 `PATH`，不会把大量库路径长期写入 shell 启动文件。

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

打开新终端后再次确认：

```bash
source ~/.bashrc
hash -r
type -a swanmerge
which swanmerge.exe
```

---

## 8. 用自己的案例执行合并测试

准备你自己的 SWAN 输入文件和对应 MPI 输出分片。本仓库不提供、也不假设任何固定测试案例名。

### 8.1 选择运行目录

应在案例运行目录中执行 `swanmerge`，不要在源码目录中直接执行，除非你的案例文件也放在源码目录里。运行目录必须可写，因为 `swanmerge` 会在这里生成临时文件和日志。

运行前需要准备好：

- `swanmerge` 已在 `PATH` 中可见，或已经安装第 7 步的用户级包装器。
- SWAN 输入文件，例如 `run_case.swn`，位于当前运行目录。
- MPI 输出分片，例如 `case.nc-001`、`case.nc-002` 等，位于 SWAN 输入文件所定义或引用的位置。
- 如果输入文件中使用相对路径，这些路径必须从当前运行目录出发是有效的。
- 如果你的 MPI 设置需要 `machinefile`，请把 `machinefile` 放在当前运行目录。

注意：`swanmerge` 脚本会取 `-input` 参数的 basename，然后在当前目录读取 `<basename>.swn`。因此，应先 `cd "$WORKDIR"`，再使用 `-input run_case.swn`，不要把绝对路径作为 `-input` 传入。

根据你的数据设置变量：

```bash
export CASE_ID=<your_case_id>
export INPUT_NAME=run_${CASE_ID}.swn
export OUTDIR=/path/to/swan/output/fragments
export WORKDIR=/path/to/swanmerge/test/workdir
export BASE=<output_basename_without_fragment_suffix>
export NPROC=<number_of_mpi_fragments>
```

检查运行目录和预期文件是否准备好：

```bash
cd "$WORKDIR"
test -f "$INPUT_NAME"
ls -1 "$OUTDIR/${BASE}.nc-"* | wc -l
```

输出数量应与 `NPROC` 一致。如果 `.swn` 文件把分片写到相对路径，请把上面检查命令中的 `OUTDIR` 设置成从 `WORKDIR` 出发能访问到的相同相对位置。

清理旧运行痕迹并执行：

```bash
cd "$WORKDIR"
rm -f swanmerge.exe INPUT norm_end PRINT PRINT-* Errfile Errfile-* \
      "merge_${CASE_ID}.log" "run_${CASE_ID}.mrg.prt"* "run_${CASE_ID}.mrg.erf"*
rm -f "$OUTDIR/${BASE}.nc"

swanmerge -input "$INPUT_NAME" -mpi "$NPROC" > "merge_${CASE_ID}.log" 2>&1
echo "run_exit_code=$?"
tail -n 80 "merge_${CASE_ID}.log"
ls -lh "$OUTDIR/${BASE}.nc"
```

成功迹象包括：`run_exit_code=0`、目标 NetCDF 文件存在、日志中出现 `Normal end of run 1`。

---

## 9. 验证 NetCDF 数值

生成 NetCDF 文件还不够，需要确认关键变量包含有效值。

```bash
export NCFILE="$OUTDIR/${BASE}.nc"
ls -lh "$NCFILE"

if [ -x "$NETCDFROOT/bin/ncdump" ]; then
  "$NETCDFROOT/bin/ncdump" -h "$NCFILE" | head -n 120
else
  echo "ncdump not found under $NETCDFROOT/bin"
fi
```

编译并运行轻量级 C 检查工具：

```bash
cd "$SWAN_CODE"
test -f check_swan_nc.c || { echo "missing check_swan_nc.c"; exit 1; }

icx -O2 -I"$NETCDFROOT/include" check_swan_nc.c \
  -L"$NETCDFROOT/lib" -lnetcdf \
  -o check_swan_nc

LD_LIBRARY_PATH="$NETCDFROOT/lib:$HDF5ROOT/lib:${LD_LIBRARY_PATH:-}" \
  ./check_swan_nc "$NCFILE"
```

至少一个重要波浪变量，例如 `hs`、`tps` 或 `tm01`，应显示 `valid > 0`。

同时检查合并日志：

```bash
grep -niE "error|failed|cannot|inconsistency|iostat|abort" \
  "merge_${CASE_ID}.log" "run_${CASE_ID}.mrg.erf"* 2>/dev/null | head -n 50
```

---

## 10. 常用命令模式

完成构建和包装器安装后，常用流程为：

```bash
cd /path/to/your/swan/workdir
test -f run_case.swn
swanmerge -input run_case.swn -mpi <number_of_mpi_fragments> > merge_case.log 2>&1
echo "exit_code=$?"
tail -n 80 merge_case.log
```

如果遇到 `Too many levels of symbolic links`，删除工作目录中的旧链接后重试：

```bash
rm -f ./swanmerge.exe
hash -r
type -a swanmerge
which swanmerge.exe
```
