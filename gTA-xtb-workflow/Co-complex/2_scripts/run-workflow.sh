#!/bin/bash

# ==============================================================================
#  分子结构迭代优化工作流脚本 (内置配置版)
#
#  功能:
#  1. 从文件顶部的配置区读取路径
#  2. 自动创建并进入工作目录
#  3. 在固定次数的循环中，执行 gTA 旋转 和 xtb 几何优化
#  4. 记录每次优化后的能量并保存最终结构
#
#  作者: Gemini
#  日期: 2025-08-09
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

# 迭代总次数
MAX_ITERATIONS=14
CHARGE=3            # 分子电荷 (用于 xtb 的 -c 参数)
UNPAIR=0            # 未成对电子个数 (用于 xtb 的 -u 参数)


# 获取脚本所在的目录，从而推断出项目根目录
# 这使得脚本可以从任何地方安全运行
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")



# --- 文件路径配置 ---
# (根据您的目录结构，这些路径应该是正确的)
INITIAL_XYZ_FILE="$PROJECT_ROOT/1_inputs/g2-co.xyz"
TARGET_GTA_OUTPUT_SUFFIX="arm_x_-5deg_arm_y_-5deg_arm_z_-5deg"  
# e.g. xtbopt_${TARGET_GTA_OUTPUT_SUFFIX}.xyz


FIX_INPUT_FILE="$PROJECT_ROOT/1_inputs/fix-input.txt"
GTA_SCRIPT_FILE="$PROJECT_ROOT/2_scripts/gTA-cli.py"
GTA_JSON_FILE="$PROJECT_ROOT/1_inputs/input.json"
WORKSPACE_DIR="$PROJECT_ROOT/4_workspace"


# 获取脚本所在的目录，从而推断出项目根目录
# 这使得脚本可以从任何地方安全运行
# SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
# PROJECT_ROOT=$(dirname "$SCRIPT_DIR")


# ==============================================================================
# --- 工作流开始 (无需修改以下部分) ---
# ==============================================================================

echo "================================================="
echo "===   分子结构迭代优化工作流启动            ==="
echo "================================================="
echo

# --- 1. 初始化 ---
echo "--- 步骤 1: 环境初始化 ---"

# 创建并进入工作目录，后续所有操作都在此进行
mkdir -p "$WORKSPACE_DIR"
# 为逐迭代保存 xtb 输出准备目录
mkdir -p "$WORKSPACE_DIR/xtb_sav"
cd "$WORKSPACE_DIR"
echo "工作目录已设置为: $WORKSPACE_DIR"



# 检查所有输入文件是否存在
for f in "$INITIAL_XYZ_FILE" "$FIX_INPUT_FILE" "$GTA_SCRIPT_FILE" "$GTA_JSON_FILE"; do
    if [ ! -f "$f" ]; then
        echo "错误: 配置文件或脚本不存在: $f" >&2
        exit 1
    fi
done
echo "所有输入文件检查完毕。"

# 准备能量日志文件
ENERGY_LOG="energy_log.csv"
echo "Iteration,Energy(Eh)" > "$ENERGY_LOG"
echo "已创建能量日志文件: $ENERGY_LOG"

# 复制初始XYZ文件作为第一次循环的输入
cp "$INITIAL_XYZ_FILE" ./xtbopt.xyz
echo "已复制初始结构到 ./xtbopt.xyz"

# 将xtb和gTA的配置文件复制到当前工作目录，方便调用
cp "$FIX_INPUT_FILE" ./fix-input-local.txt
cp "$GTA_JSON_FILE" ./input.json
echo "已准备好 xtb 和 gTA 的配置文件。"
echo

# --- 2. 主循环 ---
for i in $(seq 1 $MAX_ITERATIONS)
do
    echo "------------------ 开始第 $i / $MAX_ITERATIONS 次迭代 ------------------"

    # --- 步骤 A: gTA 旋转 ---
    echo "[步骤 A] 正在使用 gTA 旋转结构..."
    python3 "$GTA_SCRIPT_FILE" ./input.json
    #ROTATED_FILE="xtbopt/xtbopt_rotated_5deg.xyz"
    ROTATED_FILE="xtbopt/xtbopt_${TARGET_GTA_OUTPUT_SUFFIX}.xyz"
    if [ ! -f "$ROTATED_FILE" ]; then
        echo "错误: gTA 未能生成旋转文件 '$ROTATED_FILE'！" >&2
        exit 1
    fi
    echo "结构旋转完成，输出文件: $ROTATED_FILE"

    # --- 步骤 B: xtb 几何优化 ---
    echo "[步骤 B] 正在使用 xtb 进行几何优化..."
    rm -rf xtbopt.log xtbopt.xyz 
    xtb --gfn 2 "$ROTATED_FILE" --verbose -c $CHARGE -u $UNPAIR --input ./fix-input-local.txt --opt
    if [ ! -f "xtbopt.xyz" ]; then
        echo "错误: xtb 未能生成优化文件 'xtbopt.xyz'！" >&2
        exit 1
    fi
    echo "几何优化完成，输出文件: xtbopt.xyz"

    # --- 保存本轮 xtb 输出快照 ---
    SAV_DIR="./xtb_sav"
    IDX=$(printf "%03d" "$i")
    SAVE_PREFIX="I${IDX}_xtbopt"
    # 复制日志与结构，命名添加三位编号前缀
    cp -f xtbopt.log "$SAV_DIR/${SAVE_PREFIX}.log" || echo "警告: 未找到 xtbopt.log，跳过保存" >&2
    cp -f xtbopt.xyz "$SAV_DIR/${SAVE_PREFIX}.xyz" || echo "警告: 未找到 xtbopt.xyz，跳过保存" >&2
    echo "已保存第 ${i} 轮快照到: $SAV_DIR/${SAVE_PREFIX}.(log|xyz)"

    # --- 步骤 C: 记录能量 ---
    echo "[步骤 C] 正在记录能量..."
    ENERGY_VALUE=$(sed -n '2p' xtbopt.xyz | awk '{print $2}')
    if [ -z "$ENERGY_VALUE" ]; then
        echo "警告: 未能从 xtbopt.xyz 提取能量值。" >&2
    else
        echo "$i,$ENERGY_VALUE" >> "$ENERGY_LOG"
        echo "第 $i 次迭代能量: $ENERGY_VALUE Eh"
    fi
    # clean up xtb temp files
    rm -rf wbo charges xtbtopo.mol xtbrestart 
    echo
done

# --- 3. 结束 ---
echo "------------------ 工作流执行完毕 ------------------"
mv xtbopt.xyz g1_final_optimized.xyz

echo "最终优化结构已保存为: $WORKSPACE_DIR/g1_final_optimized.xyz"
echo "能量记录保存在: $WORKSPACE_DIR/energy_log.csv"
echo "================================================="

