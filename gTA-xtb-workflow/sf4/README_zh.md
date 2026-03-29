# 基于 xtb 的 gTA 扫描工作流

[English Document](./README.md)

本仓库包含一个小型工作流，用于执行迭代式 turnstile rotation 扫描，并在每一步之后进行受约束的 `xtb` 几何优化。

该工作流由 [`2_scripts/run-workflow.sh`](./2_scripts/run-workflow.sh) 驱动，其功能包括：

- 基于模板生成本地输入文件，
- 对当前结构施加基于 gTA 的旋转，
- 在每次旋转后运行受约束的 `xtb` 优化，
- 记录绝对能量和相对能量，
- 保存逐步结构以及合并后的 XYZ 轨迹。

## 依赖

主要依赖如下：

- Python 3
- `numpy`
- `scipy`
- `xtb`

`xtb` 需要单独安装，并通过以下任一方式可用：

- 通过 `-x` 传入绝对路径，
- 或者作为可执行命令存在于 `PATH` 中。

说明：

- 当前工作流基于 XYZ 输入，并设置 `first_coord_sphere_only = true`。
- 在这种模式下，实际需要的外部依赖主要是 `numpy`、`scipy` 和 `xtb`。

## 仓库结构

这里只说明与该工作流直接相关的目录。

### `1_inputs/`

工作流使用的输入文件和模板文件：

- `sf4-stable.xyz`
  默认起始结构。
- `fix-input-template.txt`
  用于生成本地 `xtb` 受约束优化输入文件的模板。通常不需要修改这个文件。
- `gta-cli_input-template.json`
  用于生成本地 gTA 旋转输入文件的模板。如果你只需要旋转一个 turnstile，通常也不需要修改这个文件。

### `2_scripts/`

核心工作流脚本：

- `run-workflow.sh`
  迭代扫描与优化工作流的主入口。
- `gTA-cli.py`
  根据生成的 JSON 输入执行 turnstile rotation。
- `utils.py`
  `gTA-cli.py` 使用的几何与旋转辅助函数。

## 使用方式

在仓库根目录下运行工作流：

```bash
bash 2_scripts/run-workflow.sh [options]
```

### 命令行参数

- `-m <int>`：扫描步数。在每一步扫描中，turnstile 会按一个小角度旋转一次
- `-a <number>`：每一步的旋转角度，单位为度
- `-c <int>`：turnstile rotation 的中心原子编号（从 1 开始）
- `-r <list>`：arm atom 的编号列表（从 1 开始），使用逗号分隔，例如 `2,3,5`
- `-q <int>`：分子电荷
- `-u <int>`：未成对电子数
- `-f <expr>`：优化时固定/约束的原子编号（从 1 开始），例如 `1,2-4,7-9`
- `-i <path>`：初始 XYZ 结构路径
- `-x <path-or-command>`：`xtb` 可执行文件路径或命令
- `-g <int>`：传递给 `xtb --gfn` 的参数值
- `-h`：打印帮助信息

### 示例

```bash
cd 2_scripts/
bash ./run-workflow.sh \
  -m 25 \
  -a '-5' \
  -c 1 \
  -r 2,3,5 \
  -q 0 \
  -u 0 \
  -f 2-5 \
  -i 1_inputs/sf4-stable.xyz \
  -x /path/to/xtb \
  -g 2
```

### 脚本会做什么

一次典型运行中，脚本会：

1. 将起始结构复制到工作目录中；
2. 基于模板生成本地 `input.json` 和 `fix-input-local.txt`；
3. 对 `iteration 0` 执行一次单点能计算；
4. 按照指定次数重复执行“旋转 + 受约束优化”循环；
5. 写出能量数据、逐步快照和累积的 XYZ 轨迹。

## 输出文件

运行过程中会生成 `4_workspace/` 目录。

重要输出文件包括：

- `4_workspace/energy_log.csv`
  能量表，包含 `Iteration`、`Energy(Eh)` 和 `Relative Energy (kcal/mol)`。
- `4_workspace/starting_geom.xyz`
  用户提供的初始结构副本。
- `4_workspace/scan-traj.xyz`
  合并后的多帧 XYZ 轨迹。第一帧为初始结构。
- `4_workspace/final_optimized.xyz`
  最后一轮迭代得到的最终优化结构。
- `4_workspace/xtb_sav/I000_xtbopt.out.txt`
  初始单点能计算的标准输出。
- `4_workspace/xtb_sav/IXXX_xtbopt.xyz`
  每一轮迭代保存的优化后结构。
- `4_workspace/xtb_sav/IXXX_xtbopt.log`
  每一轮迭代保存的原生 `xtb` 日志。
- `4_workspace/xtb_sav/IXXX_xtbopt.out.txt`
  每一步 `xtb` 优化时重定向保存的标准输出。

## 说明

- 负角度建议在命令行中加引号，例如 `-a '-5'`。
- 预期的旋转输出文件名会根据 gTA 的 alias 和所选角度自动推导。
- 相对能量以 `iteration 0` 为参考，换算因子为 `627.509`。
