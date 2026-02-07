#!/bin/bash

# ==============================================================================
#  分子结构迭代优化工作流脚本（ORCA 版）
#
#  说明：按 orca_dev_plan.md 将原 xTB 步骤替换为 ORCA 固定原子优化。
#  - gTA 与整体迭代逻辑保持不变
#  - gTA 的输入结构文件名改为 orcaopt.xyz
#  - ORCA 输入由模板生成，固定原子由 bash 数组提供（1 起始），转换为 0 起始
#  - 每轮 ORCA 产物保存至 orca_sav 并加 I%03d_ 前缀
# ==============================================================================

# --- 配置 ---
# 如果脚本出错则立即退出
set -e
# 在管道命令中，任何一步出错都算作出错
set -o pipefail


# ==============================================================================
# --- 用户配置区 ---
# 请在此处设置迭代次数和所有文件的路径。
# 脚本设计为自动定位，如果您的目录结构与推荐结构一致，则无需修改。
# ==============================================================================

## 迭代与分子整体参数
MAX_ITERATIONS=24
CHARGE=0            # 分子电荷
MULT=1              # 总自旋多重度（替代 UNPAIR）

## 固定原子列表（1 起始索引；可按需修改）
FIXED_ATOMS_1BASED=(2 3 4 5)


# 获取脚本所在的目录，从而推断出项目根目录（可从任意位置运行）
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")


# --- 文件路径配置 ---
INITIAL_XYZ_FILE="$PROJECT_ROOT/1_inputs/opted_sf4.xyz"
GTA_SCRIPT_FILE="$PROJECT_ROOT/2_scripts/gTA-cli.py"
GTA_JSON_FILE="$PROJECT_ROOT/1_inputs/input.json"
WORKSPACE_DIR="$PROJECT_ROOT/4_workspace"
ORCA_PATH="/home/raymond/packages-installed/orca-610/orca"

# gTA 旋转产物命名（与 input.json 内 alias/angle 对应）
TARGET_GTA_OUTPUT_SUFFIX="arm_1_5deg"


# ==============================================================================
# --- 工作流开始 (无需修改以下部分) ---
# ==============================================================================

echo "================================================="
echo "===   分子结构迭代优化工作流启动 (ORCA 版)   ==="
echo "================================================="
echo

# --- 1. 初始化 ---
echo "--- 步骤 1: 环境初始化 ---"

# 创建并进入工作目录，后续所有操作都在此进行
mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
echo "工作目录已设置为: $WORKSPACE_DIR"

# 检查所有输入文件是否存在
for f in "$INITIAL_XYZ_FILE" "$GTA_SCRIPT_FILE" "$GTA_JSON_FILE"; do
  if [ ! -f "$f" ]; then
    echo "错误: 配置文件或脚本不存在: $f" >&2
    exit 1
  fi
done
echo "所有输入文件检查完毕。"

mkdir -p orca orca_sav

# 准备能量日志文件
ENERGY_LOG="energy_log.csv"
echo "Iteration,Energy(Eh)" > "$ENERGY_LOG"
echo "已创建能量日志文件: $ENERGY_LOG"

# 复制初始XYZ文件作为第一次循环的输入（ORCA 版为 orcaopt.xyz）
cp "$INITIAL_XYZ_FILE" ./orcaopt.xyz
echo "已复制初始结构到 ./orcaopt.xyz"

# 将 gTA 的配置文件复制到当前工作目录，并将 input_xyz 改为 orcaopt.xyz
cp "$GTA_JSON_FILE" ./input.json
# python3 - "$PWD/input.json" <<'PY'
# import json,sys
# p=sys.argv[1]
# with open(p,'r') as f: cfg=json.load(f)
# cfg['input_xyz']='orcaopt.xyz'
# with open(p,'w') as f: json.dump(cfg,f,indent=2)
# print('已更新 input.json: input_xyz=orcaopt.xyz')
# PY
# echo

# --- 2. 主循环 ---
for i in $(seq 1 $MAX_ITERATIONS); do
  echo "------------------ 开始第 $i / $MAX_ITERATIONS 次迭代 ------------------"

  # --- 步骤 A: gTA 旋转 ---
  echo "[步骤 A] 使用 gTA 旋转结构..."
  python3 "$GTA_SCRIPT_FILE" ./input.json
  ROTATED_DIR="orcaopt"
  ROTATED_FILE="${ROTATED_DIR}/orcaopt_${TARGET_GTA_OUTPUT_SUFFIX}.xyz"
  if [ ! -f "$ROTATED_FILE" ]; then
    echo "错误: gTA 未能生成旋转文件 '$ROTATED_FILE'！" >&2
    exit 1
  fi
  echo "结构旋转完成: $ROTATED_FILE"

  # --- 步骤 B: ORCA 固定原子优化 ---
  echo "[步骤 B] 使用 ORCA 进行固定原子优化..."
  ORCA_RUN_DIR="orca"
  ORCA_SAVE_DIR="orca_sav"
  mkdir -p "$ORCA_RUN_DIR" "$ORCA_SAVE_DIR"
  rm -rf "$ORCA_RUN_DIR"/*


  # 生成 FIXED_ATOM_LINES（1→0 起始）
  FIXED_LINES=$(
  for a in "${FIXED_ATOMS_1BASED[@]}"; do
    printf '        {C %d C}\n' "$((a-1))"
  done
  )

  # 生成 XYZ_LINES（去掉 xyz 的前两行头）
  XYZ_LINES=$(tail -n +3 "$ROTATED_FILE")

  TEMPLATE="$PROJECT_ROOT/0_orca_templates/orca-fixed-opt-template.txt"
  ORCA_IN="$ORCA_RUN_DIR/FixedOpt.txt"
  {
    while IFS= read -r line; do
      if [[ "$line" == *"FIXED_ATOM_LINES"* ]]; then
        printf "%s\n" "$FIXED_LINES"
        continue
      fi
      if [[ "$line" == *"XYZ_LINES"* ]]; then
        printf "%s\n" "$XYZ_LINES"
        continue
      fi
      line=${line/CHAR/$CHARGE}
      line=${line/MULT/$MULT}
      printf "%s\n" "$line"
    done < "$TEMPLATE"
  } > "$ORCA_IN"

  ( cd "$ORCA_RUN_DIR" && $ORCA_PATH FixedOpt.txt > FixedOpt.out.txt ) || true

  # 判断是否正常结束（可选）
  if grep -q "TOTAL RUN TIME" "$ORCA_RUN_DIR/FixedOpt.out.txt" 2>/dev/null; then
    echo "ORCA 正常结束"
  else
    echo "警告: ORCA 可能未正常结束（未发现 TOTAL RUN TIME）"
  fi

  # 复制产物到保存目录并加前缀
  ITER_TAG=$(printf "I%03d" "$i")
  for f in FixedOpt.txt FixedOpt.out.txt FixedOpt_trj.xyz FixedOpt.xyz; do
    if [ -f "$ORCA_RUN_DIR/$f" ]; then
      cp -f "$ORCA_RUN_DIR/$f" "$ORCA_SAVE_DIR/${ITER_TAG}_$f"
    fi
  done

  # 将优化结果作为下一轮输入 orcaopt.xyz
  if [ -f "$ORCA_RUN_DIR/FixedOpt.xyz" ]; then
    cp -f "$ORCA_RUN_DIR/FixedOpt.xyz" ./orcaopt.xyz
    echo "已更新下一轮输入: ./orcaopt.xyz"
  else
    echo "警告: 未找到 ORCA 优化结果 FixedOpt.xyz，保留上一轮 orcaopt.xyz"
  fi

  # --- 步骤 C: 记录能量 ---
  echo "[步骤 C] 记录能量..."
  if [ -f "$ORCA_RUN_DIR/FixedOpt.xyz" ]; then
    ENERGY_VALUE=$(sed -n '2p' "$ORCA_RUN_DIR/FixedOpt.xyz" | awk '{print $NF}')
    [ -z "$ENERGY_VALUE" ] && ENERGY_VALUE=NA
  else
    ENERGY_VALUE=NA
  fi
  echo "$i,$ENERGY_VALUE" >> "$ENERGY_LOG"
  echo "第 $i 次迭代能量: $ENERGY_VALUE Eh"
  echo
done

# --- 3. 结束 ---
echo "------------------ 工作流执行完毕 ------------------"
if [ -f orcaopt.xyz ]; then
  cp -f orcaopt.xyz final_optimized.xyz
  echo "最终优化结构已保存为: $WORKSPACE_DIR/final_optimized.xyz"
else
  echo "警告: 未找到 orcaopt.xyz，无法导出最终结构"
fi
echo "能量记录保存在: $WORKSPACE_DIR/energy_log.csv"
echo "================================================="

