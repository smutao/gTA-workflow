# 基于 ORCA 的 gTA 扫描工作流

[English README](README.md)

## 概述

这个仓库包含一个用于分子迭代扫描与约束优化的小型工作流：

1. 从一个输入的 XYZ 几何结构开始。
2. 使用 `gTA-cli.py` 施加类似 turnstile 的旋转。
3. 对旋转后的结构运行 ORCA 约束几何优化。
4. 按用户指定的迭代次数重复上述过程。
5. 记录初始单点能以及后续所有优化结构的能量。

本 README 只覆盖当前工作流中实际使用到的文件和目录：

- `0_orca_templates/`
- `1_inputs/`
- `2_scripts/`


## 仓库结构

- `0_orca_templates/`
  工作流使用的 ORCA 输入模板。
  关键文件：
  - `orca-sp-energy-template.txt`
  - `orca-fixed-opt-template_nomaxcycle.txt`
  - `orca-fixed-opt-template_maxcycle.txt`

- `1_inputs/`
  工作流输入文件。
  关键文件：
  - `opted_sf4.xyz`
  - `gta-cli_input-template.json`

- `2_scripts/`
  工作流使用的脚本。
  关键文件：
  - `run-workflow.sh`
  - `gTA-cli.py`
  - `utils.py`


## 依赖

当前工作流需要：

- Python 3
- `numpy`
- `scipy`
- ORCA 6.0 或更高版本

说明：

- `run-workflow.sh` 是一个 Bash 脚本。
- ORCA 可执行程序既可以直接调用，也可以通过 `singularity exec ... orca` 这样的包装命令调用。
- 当前工作流基于 XYZ 输入驱动，因此这里只列出了实际使用到的 Python 依赖。


## 工作流输入

该工作流需要以下输入：

- 一个初始 XYZ 几何结构，默认是 `1_inputs/opted_sf4.xyz`
- 一个 gTA JSON 模板文件，即 `1_inputs/gta-cli_input-template.json`
- 位于 `0_orca_templates/` 中的 ORCA 模板文件

运行脚本会通过替换以下占位符，从 JSON 模板生成 gTA 实际使用的 `input.json`：

- `GTA_ANCHOR_ATOM`
- `GTA_ARM_ATOMS`
- `GTA_ANGLE`


## 使用方式

从仓库根目录运行该工作流：

```bash
cd 2_scripts/
bash ./run-workflow.sh [options]
```

主要参数：

- `-m`
  扫描/优化的迭代次数，它决定要扫描多少个 turnstile rotation 步

- `-a`
  每一步扫描所使用的 gTA 旋转角度（单位为度），必须是整数，例如 `5` 或 `"-5"`

- `-c`
  作为 `anchor_atom` 使用的中心原子编号

- `-r`
  作为 `arm_atoms` 使用的 arm 原子编号
  格式示例：`"2,4,5"` 或 `"2-4,7"`

- `-q`
  分子电荷

- `-u`
  分子自旋多重度

- `-f`
  ORCA 约束优化中固定的原子编号
  格式示例：`"1,2-4,7-9"`

- `-i`
  初始 XYZ 几何结构路径

- `-n`
  每一步扫描中 ORCA 几何优化的最大循环次数
  如果提供该参数，工作流会使用 `orca-fixed-opt-template_maxcycle.txt` 并替换其中的 `GEOM_MAX_CYCLE`

- `-k`
  完整的 ORCA 执行命令
  当 ORCA 通过容器包装命令启动时，这个参数很有用


## 示例

```bash
./2_scripts/run-workflow.sh \
  -m 24 \
  -a "5" \
  -c 1 \
  -r "2,4,5" \
  -q 0 \
  -u 1 \
  -f "2-5" \
  -n 50 \
  -i 1_inputs/opted_sf4.xyz \
  -k "/path/to/orca"
```


## 脚本具体做什么

`2_scripts/run-workflow.sh` 会执行以下步骤：

1. 检查所需文件和参数是否合法。
2. 将初始 XYZ 结构复制到运行时工作目录。
3. 从 `1_inputs/gta-cli_input-template.json` 生成运行时 `input.json`。
4. 对初始结构执行一次 ORCA 单点能计算。
5. 进入迭代循环：
   - 使用 gTA 旋转结构
   - 运行 ORCA 约束优化
   - 更新下一轮迭代所用的当前结构
   - 将能量追加写入日志


## 使用建议

- 如果 `run-workflow.sh` 中默认的 ORCA 命令在你的机器上不可用，请通过 `-k` 传入你自己的命令。
- 如果使用负旋转角度，建议加引号，例如 `-a "-5"`。
- `-f` 和 `-r` 支持紧凑的原子区间语法，例如 `"1,2-4,7"`。
