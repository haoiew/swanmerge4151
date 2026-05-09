# SWANMERGE 离线依赖构建指南

[English version](SWANMERGE_Offline_Repro_Guide.md)

只有在以下情况之一出现时，才需要使用本指南：

1. 目标 Linux 服务器缺少 METIS、HDF5、NetCDF-C 或 NetCDF-Fortran；
2. `ldd swanmerge.exe` 显示链接到了不兼容的 MPI 家族；
3. 服务器没有外网，需要在其他机器下载源码包后再复制到服务器。

如果主构建指南已经找到兼容依赖，并且 `ldd` 没有显示 MPI ABI 混用，可以跳过本指南。

---

## 1. 检查缺少什么

不要默认重装依赖。能复用当前服务器上 ABI 兼容的库，就优先复用。

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

如果已经构建过 `swanmerge.exe`，检查动态库链接：

```bash
ldd "${SWAN_CODE:-/path/to/swanmerge4151}/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf" || true
```

如果出现两个不兼容的 MPI 家族，请用与 SWANMERGE 相同的编译器/MPI 栈重建 HDF5/NetCDF。

---

## 2. 准备源码包

当服务器没有外网时，在另一台机器下载所需源码包，然后复制到服务器。

常见源码包名称如下：

```text
METIS 缺失：metis-5.1.0.tar.gz
HDF5 缺失或 MPI ABI 冲突：hdf5-1.14.5.tar.gz
NetCDF-C 缺失或 MPI ABI 冲突：netcdf-c-4.9.2.tar.gz
NetCDF-Fortran 缺失或 MPI ABI 冲突：netcdf-fortran-4.6.1.tar.gz
zlib 头文件缺失：zlib-1.3.1.tar.gz
```

设置包目录并确认文件：

```bash
export PKGROOT=/path/to/offline_pkgs
mkdir -p "$PKGROOT"
ls -lh "$PKGROOT"/*.tar.gz
```

不要依赖 `v4.9.2.tar.gz` 这类自动生成的压缩包名称；建议重命名为下面命令中使用的明确文件名。

---

## 3. 设置隔离安装前缀

安装到用户可控目录，不覆盖系统库：

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

## 4. 只在需要时安装 METIS

先确认没有可用的 METIS 库：

```bash
find $SWANMERGE_SEARCH_ROOTS -type f \( -name 'libmetis.a' -o -name 'libmetis.so*' \) -printf '%h/%f\n' 2>/dev/null | head
```

如果命令已经找到兼容库，回到主构建指南设置 `METISLIBDIR` 即可。只有确实缺少库文件时才安装 METIS：

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

有些 METIS 构建会提供 `libGKlib`，有些不会。主构建指南会自动判断，不需要手工固定。

---

## 5. 只在需要时安装 HDF5

下面命令使用 Intel 编译器构建串行 HDF5。这不会让 SWANMERGE 变成串行程序；它只是避免 NetCDF/HDF5 链接到不兼容的 MPI ABI。

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

如果缺少 zlib，先安装到同一隔离前缀：

```bash
cd "$SRCROOT"
tar -xf "$PKGROOT/zlib-1.3.1.tar.gz"
cd zlib-1.3.1
CC=icx ./configure --prefix="$PREFIX/zlib"
make -j"$JOBS"
make install
```

然后重新配置 HDF5，并添加：

```bash
--with-zlib="$PREFIX/zlib"
```

---

## 6. 只在需要时安装 NetCDF-C

关闭 DAP 和 parallel4，减少离线依赖并避免 MPI ABI 混用：

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

## 7. 只在需要时安装 NetCDF-Fortran

SWANMERGE 需要 `netcdf.mod` 和 `libnetcdff.so`：

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

`libnetcdff.so` 应能链接到 `libnetcdf.so`，但不应引入不兼容的 MPI 库。

---

## 8. 使用隔离依赖重新构建 SWANMERGE

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

然后回到主构建指南，从生成 `macros.inc` 步骤继续。

---

## 9. 最终 ABI 检查

```bash
ldd "$SWAN_CODE/swanmerge.exe" | egrep -i "libmpi.so|libmpifort|libhdf5|libnetcdf"
```

可接受结果应只包含一个 MPI 家族，例如 Intel oneAPI MPI 加上 ABI 兼容的 NetCDF/HDF5 库。

如果同时出现 Intel MPI 和 OpenMPI 库，请检查 `LD_LIBRARY_PATH`、`macros.inc`，以及 `libnetcdf.so`、`libhdf5.so` 的 `ldd` 输出，然后用一致的依赖栈重新构建。

---

## 10. 关键点

`BLKNDC = REAL(ipown)` 解决的是部分非结构网格合并场景中 NetCDF 合并结果全缺失值的问题。隔离 HDF5/NetCDF 构建解决的是缺依赖或 MPI ABI 混用问题。二者解决的问题不同，不能互相替代。
