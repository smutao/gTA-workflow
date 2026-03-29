# gTA-cli

[English README](./README.md)

`gTA-cli` 是一个小型命令行工具，用于对分子几何结构施加广义 turnstile-angle 旋转，并将结果结构导出为 XYZ 文件。

它支持：

- `SDF` 输入，并通过 `RDKit` 基于连通性选择要旋转的片段
- `XYZ` 输入，并显式指定第一配位层要旋转的原子
- 单个 transformation/turnstile 在多个角度上的扫描
- 多个 transformation group 的角度笛卡尔积组合生成

## 依赖

代码基于 Python 3，依赖如下：

- `numpy`
- `scipy`
- `rdkit`

实际说明：

- `numpy` 在所有模式下都需要。
- `scipy` 用于圆心优化步骤。
- 使用 `input_sdf` 时需要 `rdkit`。
- 如果你只使用 `input_xyz` 且设置 `first_coord_sphere_only = true`，实际需要的 Python 依赖主要是 `numpy` 和 `scipy`。

安装示例：

```bash
pip install numpy scipy
```

对于 `rdkit`，建议使用适合你环境的包源，例如 `conda-forge`。

## 仓库结构

- `code/gTA-cli.py`：主 CLI 入口
- `code/utils.py`：几何、旋转和连通性相关工具函数
- `examples/g1/`：基于 `SDF` 的单个 transformation/turnstile 示例
- `examples/g2/`：基于 `XYZ` 的多个 transformation/turnstile 示例

## 运行方式

通过传入一个 JSON 配置文件来运行脚本：

```bash
python3 code/gTA-cli.py path/to/input.json
```

如果不传参数，脚本会回退到内部默认路径。实际使用中，建议始终显式传入 JSON 文件。

在 `gTA-cli/` 目录下的示例：

```bash
python3 code/gTA-cli.py examples/g1/g1-babel-1.json
python3 code/gTA-cli.py examples/g2/g2-co-2.json
```

## 脚本会做什么

对于每一个 transformation 定义，`gTA-cli` 会：

1. 从 `SDF` 或 `XYZ` 读取输入结构
2. 提取 `anchor_atom` 和 `arm_atoms`
3. 基于 anchor 点和优化后的 circle center 计算旋转轴
4. 选出需要旋转的原子
5. 按要求的角度对选中的原子进行旋转
6. 写出一个或多个 XYZ 输出文件

如果存在多个 transformation group，也就是多个 turnstile，工具会对各组角度生成所有组合，并为每个组合写出一个 XYZ 文件。换句话说，这个工具可以同时旋转多个 turnstile。

## JSON 配置

输入文件是一个 JSON 对象，包含顶层设置，以及一个收集所有待旋转 turnstile 的 `transformations` 列表。

### 顶层字段

- `input_sdf`：SDF 文件路径，相对于 JSON 文件所在目录
- `input_xyz`：XYZ 文件路径，相对于 JSON 文件所在目录
- `index_start_from`：原子编号起始约定，通常为 `1`
- `first_coord_sphere_only`：可选布尔值，表示是否只旋转第一配位层原子，默认 `false`
- `transformations`：transformation 对象列表，也就是各个 turnstile

规则：

- `input_sdf` 和 `input_xyz` 必须且只能提供一个。
- 如果使用 `input_xyz`，则 `first_coord_sphere_only` 必须为 `true`。
- 路径是相对于 JSON 文件目录解析的，不是相对于当前 shell 工作目录。

### Transformation 对象

`transformations` 中的每一项都必须包含：

- `alias`：输出文件名中使用的短名称
- `anchor_atom`：中心原子编号
- `arm_atoms`：arm 原子编号列表
- `angle`：旋转角度列表，单位为度

### 示例：SDF 模式

```json
{
  "input_sdf": "g1-babel.sdf",
  "index_start_from": 1,
  "transformations": [
    {
      "alias": "arm_1",
      "anchor_atom": 1,
      "arm_atoms": [2, 5],
      "angle": [20]
    }
  ]
}
```

### 示例：XYZ 模式

```json
{
  "input_xyz": "g2-co.xyz",
  "index_start_from": 1,
  "first_coord_sphere_only": true,
  "transformations": [
    {
      "alias": "arm_x",
      "anchor_atom": 1,
      "arm_atoms": [3, 4],
      "angle": [10, 20, 30]
    },
    {
      "alias": "arm_y",
      "anchor_atom": 1,
      "arm_atoms": [2, 7],
      "angle": [10, 20, 30]
    }
  ]
}
```

## 原子选择行为

实际被旋转的原子集合取决于输入模式。

### SDF 模式

当使用 `input_sdf` 且 `first_coord_sphere_only` 为 `false` 时，脚本会：

- 通过 `RDKit` 构建分子的邻接矩阵
- 断开 `anchor_atom` 与各个 `arm_atoms` 之间的键
- 从 arm atoms 出发找到对应的连通片段
- 旋转整个片段

这就是基于连通性的模式。

### XYZ 模式

当使用 `input_xyz` 时，脚本无法推断键连信息。因此：

- `first_coord_sphere_only` 必须为 `true`
- 只有 `arm_atoms` 中列出的原子会被旋转

## 单个与多个 Transformations

如果 JSON 中只包含一个 transformation group：

- 脚本会对该组中的每个角度输出一个 XYZ 文件

如果 JSON 中包含多个 transformation groups：

- 脚本会对所有角度列表生成笛卡尔积组合
- 脚本会为每个完整组合输出一个 XYZ 文件
- 脚本还会生成按组划分的 debug 输出

## 输出文件

输出会创建在输入结构旁边的目录中：

- 主输出目录：`<input_stem>/`
- 调试目录：`<input_stem>/debug/`

典型文件名：

- 单个 transformation：`<input_stem>_<alias>_<angle>deg.xyz`
- 多个 transformations：`<input_stem>_<alias1>_<angle1>deg_<alias2>_<angle2>deg.xyz`

调试目录中可能包含一些辅助 XYZ 文件，用于检查推导得到的 circle center 和参考几何。

## 校验规则

脚本在处理前会校验一些常见配置错误：

- 输入文件缺失
- 同时使用 `input_sdf` 和 `input_xyz`
- `input_sdf` 和 `input_xyz` 都未提供
- 声明的输入类型与文件扩展名不匹配
- transformation alias 重复
- 在基于连通性的 SDF 模式下，不同 transformation groups 对应的旋转片段发生重叠

## 说明与限制

- 原子编号既可以通过 `index_start_from` 解释为 1-based，也可以解释为 0-based，但当前示例使用的是 `1`。
- `XYZ` 模式被有意限制，因为纯 XYZ 文件不包含成键信息。
- 主脚本在模块导入阶段就会导入 `RDKit`，因此即使你只打算运行 XYZ-only 输入，在没有 `rdkit` 的环境中仍然可能失败。如果你希望严格做到可选依赖行为，需要在代码层面重构。
- 该工具目前是脚本式工具，不是带安装器的 Python package。
