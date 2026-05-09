# SWANMERGE 41.51

[English README](README.md)

SWANMERGE 是 SWAN 41.51 的 merge-only 拓展分支，重点是构建和运行独立的合并程序 `swanmerge.exe`，用于合并 SWAN MPI 并行计算产生的 NetCDF 分片输出。

本项目面向 SWAN MPI 输出的后处理合并流程，不使用完整 SWAN 波浪数值计算流程。它保留 SWAN 41.51 的源码组织方式，只补充 merge 路径所需的构建、运行和验证支持。

## 适用场景

当以下条件同时满足时，本项目适用：

- 你已经用 SWAN 的 MPI 模式完成计算，并得到类似 `case.nc-001`、`case.nc-002` 这样的按进程输出分片。
- 你需要一个独立命令把这些分片合并成一个 NetCDF 文件，而不是重新运行完整波浪计算。
- 你的案例输出和网格设置与 SWAN 原始 merge 路径兼容。
- 你可以在 Linux 系统上从源码构建 SWAN，并具备 Intel oneAPI、MPI、METIS、HDF5 和 NetCDF 环境。

本项目最主要的实际目标，是处理非结构网格 SWAN NetCDF 分片合并中“文件生成了，但合并结果变量全是缺失值”的问题。本源码树包含 `SWMERGE` 路径，以及该场景中使用的 `BLKNDC = REAL(ipown)` 合并修复。

## 不适用场景

本仓库不提供公开完整 SWAN benchmark 案例，不包含水深、风场、边界谱、台风案例或任何私有模型输出。用户需要使用自己的 SWAN 输入文件和 MPI 输出分片进行测试。

本项目也不用于：

- 替代用于波浪模拟的完整 SWAN 构建；
- 修改 SWAN 物理过程或率定默认值；
- 提供通用 SWAN 建模教学；
- 为所有编译器和 MPI 组合提供预编译二进制文件；
- 在未检查原始模型设置和输出的情况下，保证合并结果具有科学有效性。

## 相比 SWAN 41.51 的变化

项目保留原始 SWAN 源文件和许可证头。本分支在 merge 相关范围内添加或修改了以下内容：

- `Makefile`：增加 `make merge` 和 `swanmerge.exe` 构建目标。
- `switch.pl`：增加 `-merge` 开关，用于启用仅合并源码段。
- `swanmain.ftn`：包含 `SWMERGE` 路径和合并相关修复，包括非结构网格合并流程使用的 ownership 字段赋值。
- `swanmerge`、`swanmerge_run.sh`、`swanmerge_env.sh`：用于加载依赖和执行合并任务的运行包装脚本。
- `check_swan_nc.c`：轻量级 NetCDF 数值检查工具，用于确认合并结果不是全缺失值。
- `SWANMERGE_SourceBuild_Run_Guide.zh-CN.md`：源码构建、部署、运行和验证流程中文版。
- `SWANMERGE_Offline_Repro_Guide.zh-CN.md`：无合适依赖或无外网服务器上的离线依赖构建流程中文版。

## 快速开始

在 Linux 上从仓库根目录构建：

```bash
export SWAN_CODE=/path/to/swanmerge4151
cd "$SWAN_CODE"
```

完整流程见 [SWANMERGE_SourceBuild_Run_Guide.zh-CN.md](SWANMERGE_SourceBuild_Run_Guide.zh-CN.md)。简化版如下：

```bash
export ONEAPI_SETVARS=${ONEAPI_SETVARS:-/opt/intel/oneapi/setvars.sh}
source "$ONEAPI_SETVARS" --force

# 根据你的机器设置依赖库前缀。
export METISROOT=/path/to/metis
export METISLIBDIR=/path/to/metis/lib
export NETCDFROOT=/path/to/netcdf
export HDF5ROOT=/path/to/hdf5

# 按构建指南生成 macros.inc 后执行：
make clobber
make merge
```

在案例运行目录中，用你自己的 SWAN 案例运行：

```bash
cd /path/to/your/swan/workdir
test -f run_case.swn
swanmerge -input run_case.swn -mpi <number_of_mpi_fragments> > merge_case.log 2>&1
```

当前目录很重要。`swanmerge` 会把当前目录中的 `run_case.swn` 复制成 `INPUT`，并在当前目录写出 `PRINT*`、`Errfile*`、`norm_end` 和合并日志。SWAN MPI 输出分片必须位于 `run_case.swn` 中定义或引用的位置；如果输入文件中使用相对路径，这些路径会相对于当前运行目录解析。

随后按构建指南中的方法，用 `ncdump` 和 `check_swan_nc.c` 验证合并后的 NetCDF 文件。

## 依赖

典型构建依赖包括：

- Perl 和 Make
- Intel oneAPI `ifx`、`mpiifx` 和 Intel MPI runtime
- METIS
- HDF5
- NetCDF-C
- NetCDF-Fortran
- 用于编译 `check_swan_nc.c` 的 C 编译器

包装脚本不假设固定服务器路径。可按实际机器设置 `ONEAPI_SETVARS`、`SWANMERGE_HOME`、`NCROOT`、`H5ROOT`、`METISROOT`、`METISLIBDIR` 或 `SWANMERGE_SEARCH_ROOTS`。

## 使用自己的数据测试

在发布或使用合并结果前，至少检查三点：

1. `swanmerge` 退出码为 `0`，日志中出现 `Normal end of run`。
2. 目标合并 `.nc` 文件存在。
3. `hs`、`tps`、`tm01` 等关键变量有有效值，而不是全缺失值。

随附的 `check_swan_nc.c` 会读取若干 NetCDF 变量并输出 `valid/total/min/max`。

## 许可证和上游状态

SWANMERGE 按 GNU General Public License version 3 or later 发布。见 [LICENSE](LICENSE)。

原始 SWAN 模型由 Delft University of Technology 开发，并按 GNU GPL 发布。本仓库保留原始 SWAN 版权和许可证头。

在学术或业务工作中使用本软件时，应引用原始 SWAN 模型和相关论文。见 [CITATION.cff](CITATION.cff) 和 [NOTICE](NOTICE)。

## 引用

SWAN 的核心参考文献为：

Booij, N., Ris, R. C., and Holthuijsen, L. H. (1999). A third-generation wave model for coastal regions: 1. Model description and validation. Journal of Geophysical Research: Oceans, 104(C4), 7649-7666. https://doi.org/10.1029/98JC02622

如果 SWANMERGE 的合并修复对你的工作有实质影响，也请引用本仓库。
