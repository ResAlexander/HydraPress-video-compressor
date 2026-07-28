#!/bin/bash
# ============================================================
#  compress_videos.sh — 视觉无损视频批量压缩工具
#
#  用途: 扫描指定目录，将 H.264 视频批量转码为 HEVC (H.265)
#        在视觉无损的前提下大幅减小文件体积
#
#  特性:
#    - 输出到独立目录，永不修改/删除源文件
#    - 已压缩文件自动跳过，支持中断后恢复
#    - nice 降低系统优先级，后台运行不干扰前台
#    - caffeinate 阻止系统休眠
#    - 完成后 macOS 弹窗通知
#
#  用法:
#    chmod +x compress_videos.sh
#    ./compress_videos.sh              # 使用下方默认配置
#    ./compress_videos.sh -i /path/in  # 命令行覆盖输入目录
#    ./compress_videos.sh -i /in -o /out -c 22 -p fast
#
#  依赖: ffmpeg, bc (macOS 自带), nice, caffeinate
# ============================================================

set -uo pipefail

# ===================== 用户配置区 =====================
# 修改以下变量或通过命令行参数覆盖
#
#   -i, --input   源视频目录
#   -o, --output  输出目录 (默认: 源目录_compressed)
#   -c, --crf     CRF 值 (默认22，越小质量越高，推荐18~28)
#   -p, --preset  编码速度预设 (默认slow，可选: ultrafast~veryslow)
#   -n, --nice    nice 优先级 (默认10，0=不降级，19=最低)
#   -f, --filter  文件名匹配 (默认 *.mp4)
#   --subdirs     递归处理子目录 (默认关闭)
#   --no-notify   禁用完成通知
#   --help        显示帮助
# -----------------------------------------------------

INPUT_DIR=""                                    # 源视频目录 (必填，或用 -i)
OUTPUT_DIR=""                                   # 输出目录 (留空则自动设为 源目录_compressed)
CRF=22                                          # CRF 质量值: 18=视觉无损，22=默认推荐，28=高压缩
PRESET="slow"                                   # 编码预设: 越慢质量越好/体积越小
NICE_LEVEL=10                                   # nice 优先级: 0=正常，10=低，19=最低
FILE_PATTERN="*.mp4"                            # 源文件名匹配模式
SUB_DIRS=false                                  # 是否递归处理子目录
NOTIFICATION=true                               # 完成后弹出 macOS 通知

# =====================================================
#  以下为脚本内部逻辑，通常无需修改
# =====================================================

# ---------- 帮助系统 ----------
# 帮助内容分别维护在 txt 文件中:
#   -h   → help_short.txt (快速帮助)
#   --help → help_full.txt (完整指南)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

show_help() {
    cat "$SCRIPT_DIR/help_short.txt"
}

show_full_guide() {
    cat "$SCRIPT_DIR/help_full.txt"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--input)   INPUT_DIR="$2";    shift 2 ;;
        -o|--output)  OUTPUT_DIR="$2";   shift 2 ;;
        -c|--crf)     CRF="$2";          shift 2 ;;
        -p|--preset)  PRESET="$2";       shift 2 ;;
        -n|--nice)    NICE_LEVEL="$2";   shift 2 ;;
        -f|--filter)  FILE_PATTERN="$2"; shift 2 ;;
        --subdirs)    SUB_DIRS=true;     shift ;;
        --no-notify)  NOTIFICATION=false; shift ;;
        -h)           show_help; exit 0 ;;
        --help)       show_full_guide; exit 0 ;;
        *)            echo "未知参数: $1"; echo "运行 -h 查看快速帮助，--help 查看完整说明"; exit 1 ;;
    esac
done

# ---------- 前置检查 ----------
check_deps() {
    local missing=()
    command -v ffmpeg >/dev/null 2>&1 || missing+=("ffmpeg")
    command -v bc     >/dev/null 2>&1 || missing+=("bc")
    if [ ${#missing[@]} -gt 0 ]; then
        echo "[错误] 缺少依赖: ${missing[*]}"
        echo "  macOS: brew install ${missing[*]}"
        exit 1
    fi
}

# 格式化文件大小为可读字符串 (字节 → KB/MB/GB)
human_size() {
    local bytes=$1
    if [ "$bytes" -gt 1073741824 ]; then
        echo "scale=1; $bytes / 1073741824" | bc
        echo " GB"
    elif [ "$bytes" -gt 1048576 ]; then
        echo "scale=1; $bytes / 1048576" | bc
        echo " MB"
    else
        echo "scale=1; $bytes / 1024" | bc
        echo " KB"
    fi
}

check_deps

# 阻止系统休眠 (caffeinate 在后台运行，脚本退出时自动结束)
caffeinate -i -w $$ &

# ---------- 目录校验 ----------
if [ -z "$INPUT_DIR" ]; then
    echo "[错误] 请指定源视频目录: $0 -i /path/to/videos"
    exit 1
fi

if [ ! -d "$INPUT_DIR" ]; then
    echo "[错误] 源目录不存在: $INPUT_DIR"
    exit 1
fi

# 输出目录默认为 源目录名_compressed
if [ -z "$OUTPUT_DIR" ]; then
    OUTPUT_DIR="${INPUT_DIR%/}_compressed"
fi

mkdir -p "$OUTPUT_DIR"

# ---------- 扫描源文件 ----------
# 用 find + print0 安全处理含空格的文件名
find_args=("$INPUT_DIR")
if [ "$SUB_DIRS" = false ]; then
    find_args+=("-maxdepth" "1")
fi

files=()
while IFS= read -r -d '' f; do
    files+=("$f")
done < <(find "${find_args[@]}" -type f -name "$FILE_PATTERN" -print0)

total=${#files[@]}

if [ "$total" -eq 0 ]; then
    echo "[错误] 在 $INPUT_DIR 中未找到 $FILE_PATTERN 文件"
    exit 1
fi

# ---------- 打印配置摘要 ----------
echo ""
echo "=========================================="
echo "  批量视频压缩"
echo "  源目录:     $INPUT_DIR"
echo "  输出目录:   $OUTPUT_DIR"
echo "  文件模式:   $FILE_PATTERN"
echo "  子目录:     $([ "$SUB_DIRS" = true ] && echo "是" || echo "否")"
echo "  待处理:     $total 个文件"
echo "  编码器:     libx265 (preset=$PRESET, crf=$CRF, 8-bit)"
echo "  优先级:     nice -n $NICE_LEVEL"
echo "  源文件不会被修改或删除"
echo "=========================================="
echo ""

# ---------- 统计变量 ----------
total_input_size=0
total_output_size=0
processed=0
skipped=0
failed=0

# ---------- 逐个处理 ----------
for f in "${files[@]}"; do
    filename=$(basename "$f")
    output="$OUTPUT_DIR/$filename"

    # 跳过已存在的输出文件 (支持中断后恢复)
    if [ -f "$output" ]; then
        echo "[$(date '+%H:%M:%S')] 跳过: $filename (已存在)"
        skipped=$((skipped + 1))
        continue
    fi

    # 统计输入文件大小
    input_size=$(stat -f%z "$f")
    total_input_size=$((total_input_size + input_size))
    input_size_str=$(human_size "$input_size")

    echo "[$(date '+%H:%M:%S')] [$((processed + skipped + 1))/$total] 处理: $filename ($input_size_str)"

    # ---------- 调用 ffmpeg 转码 ----------
    # -c:v libx265   使用 HEVC 编码
    # -tag:v hvc1    确保 Apple 设备兼容 (QuickTime/iOS)
    # -c:a copy      音频直接复制，不重新编码
    # -pix_fmt yuv420p  8-bit 4:2:0 (兼容性最好，速度最快)
    # -progress pipe:1  输出实时进度
    set +e
    nice -n "$NICE_LEVEL" ffmpeg -y -i "$f" \
        -c:v libx265 \
        -preset "$PRESET" \
        -crf "$CRF" \
        -pix_fmt yuv420p \
        -tag:v hvc1 \
        -c:a copy \
        -progress pipe:1 \
        "$output" 2>&1 | grep -E '^(frame=|fps=|bitrate=|total_size=)' | while read -r line; do
            echo "  $line"
        done
    ffmpeg_status=$?
    set -e

    # ---------- 处理结果 ----------
    if [ $ffmpeg_status -eq 0 ] && [ -f "$output" ]; then
        processed=$((processed + 1))
        output_size=$(stat -f%z "$output")
        total_output_size=$((total_output_size + output_size))

        # 计算节省比例
        savings=$(echo "scale=1; (1 - $output_size / $input_size) * 100" | bc)
        output_size_str=$(human_size "$output_size")

        echo "  完成: $filename  ($input_size_str -> $output_size_str, 节省 ${savings}%)"
    else
        failed=$((failed + 1))
        echo "  失败: $filename"
        # 只删除失败产生的残余文件，绝不触碰源文件
        [ -f "$output" ] && rm "$output"
    fi
    echo ""
done

# ---------- 最终报告 ----------
total_savings=""
if [ "$total_input_size" -gt 0 ] && [ "$total_output_size" -gt 0 ]; then
    total_savings=$(echo "scale=1; (1 - $total_output_size / $total_input_size) * 100" | bc)
fi

echo ""
echo "=========================================="
echo "  压缩报告"
echo "  完成:   $processed 个"
echo "  跳过:   $skipped 个"
echo "  失败:   $failed 个"
if [ -n "$total_savings" ]; then
    echo "  压缩前: $(echo "scale=2; $total_input_size / 1073741824" | bc) GB"
    echo "  压缩后: $(echo "scale=2; $total_output_size / 1073741824" | bc) GB"
    echo "  节省:   ${total_savings}%"
fi
echo "=========================================="

# ---------- macOS 通知 ----------
if [ "$NOTIFICATION" = true ] && [ "$processed" -gt 0 ]; then
    msg="视频压缩完成"
    [ "$skipped" -gt 0 ] && msg="$msg (${skipped}个跳过)"
    [ "$failed" -gt 0 ]  && msg="$msg (${failed}个失败)"
    msg="$msg (共${processed}个)"

    osascript -e "display notification \"${msg}\" with title \"视频压缩\" sound name \"Ping\""
fi

echo ""
echo "输出目录: $OUTPUT_DIR"
