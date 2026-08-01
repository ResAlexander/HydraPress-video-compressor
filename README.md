# hydrapress — 跨平台 HEVC 视频批量压缩工具

> 将手机拍摄的 H.264 视频批量压缩为 HEVC（H.265），在保持高画质的前提下大幅减小文件体积
>
> 支持平台：macOS · Windows (WSL2 / Git Bash) · Linux

[![macOS](https://img.shields.io/badge/-macOS-lightgrey.svg?logo=macos&logoWidth=14)](https://img.shields.io/badge/license-MIT-blue.svg)
[![Linux](https://img.shields.io/badge/-Linux-orange.svg?logo=linux&logoWidth=14)](https://img.shields.io/badge/license-MIT-blue.svg)
[![Windows](https://img.shields.io/badge/-Windows-blue.svg?logo=windows&logoWidth=14)](https://img.shields.io/badge/license-MIT-blue.svg)
[![ffmpeg](https://img.shields.io/badge/ffmpeg-5.1.2-green.svg)](https://img.shields.io/badge/bash-lightgrey.svg)

**特点**  
- 🚀 批量处理，断点续传，后台运行  
- 🔒 源文件零风险，永不修改或删除）  
- ⚡ 原文件写入 .part 临时文件，中断恢复安全  
- 📊 实时进度条 + 压缩报告，清晰直观  
- 🎯 一键 Profile 配置，无需深入理解 CRF/preset  
- 🔄 `--subdirs` 支持递归子目录，自动保留相对路径  

---

## 快速开始

```bash
# 1. 安装依赖（已安装可跳过）
brew install ffmpeg                    # macOS
sudo apt install ffmpeg bc             # Debian / Ubuntu
sudo dnf install ffmpeg bc             # Fedora / RHEL / CentOS

# 2. 下载脚本并授予执行权限
chmod +x hydrapress

# 3. 开始压缩（推荐配置）
./hydrapress -i ./Video --profile balanced
```

运行完成后，压缩后的视频会出现在 `./Video_compressed/` 目录。

### Windows (WSL2 / Git Bash)

本工具为 Bash 脚本，Windows 请通过 **WSL2** 或 **Git Bash** 运行（原生 CMD / PowerShell 不支持）：

```bash
# 方式一: WSL2 (推荐) —— 进入 Linux 子系统后与 Linux 用法一致
#   在 WSL 内: sudo apt install ffmpeg bc
#   访问 Windows 视频: /mnt/c/Users/<你的用户名>/Videos
./hydrapress -i /mnt/c/Users/you/Videos --profile balanced

# 方式二: Git Bash —— 需先自行安装 ffmpeg 与 bc，
#   且脚本会以 wc -c 兜底获取文件大小，功能完整
./hydrapress -i ./Video --profile balanced
```

> 提示: 在 Git Bash 中 `nice` 默认不可用，`-n` 参数会被忽略；WSL2 中则正常生效。

---

## 配置指南

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-i, --input` | 必填 | 源视频目录 |
| `-o, --output` | `源目录_compressed` | 输出目录 |
| `--profile` | - | 一键配置（archive/balanced/fast/maxcompress），覆盖 `-c`/`-p` |
| `-c, --crf` | `22` | CRF 质量值（14-16 视觉无损，18-20 高画质） |
| `-p, --preset` | `slow` | 编码预设 |
| `-n, --nice` | `10` | 进程优先级（0=正常，19=最低） |
| `-f, --filter` | `*.mp4` | 文件匹配模式 |
| `-b, --bit` | `auto` | 色深（8/10/12/auto） |
| `--subdirs` | - | 递归处理子目录 |
| `--no-notify` | - | 禁用完成通知 |

### Profile 一键配置

| Profile | Preset | CRF | 场景 | 预期输出* |
|---------|--------|-----|------|----------|
| `archive` | slow | 18 | 收藏归档，质量优先 | 60-80% 源体积 |
| `balanced` | fast | 20 | 日常使用，速度质量平衡 | 40-50% 源体积 |
| `fast` | ultrafast | 14 | 快速处理，文件较大 | 60-95% 源体积 |
| `maxcompress` | slow | 24 | 极限压缩，可见画质损失 | 20-35% 源体积 |

> 基于 ~16Mbps OPPO 手机视频实测数据，实际效果因内容而异。

---

## 高级选项

### CRF 参数

- **14-16** — 视觉无损（推荐收藏归档）
- **18-20** — 极高画质，体积更小
- **22** — 高质量，默认值
- **24+** — 视觉有损

### Preset 编码速度预设

⚠️ 在压缩率方面，x265 的 preset 行为与 x264 相反。

在相同 CRF 下：
- `slow` → 文件最大，质量最优（最慢）
- `ultrafast` → 文件最小，质量略低（最快）

| Preset | 速度 | 质量（SSIM） | 推荐场景 |
|--------|------|------------|----------|
| `ultrafast` | 1× | 略低 | 快速处理 |
| `fast` | 1.5× | 中等 | 日常使用 |
| `slow` | 3× | 最高 | 收藏归档 |

---

## 使用示例

```bash
# 收藏归档（质量优先）
./hydrapress -i ./Videos --profile archive --subdirs

# 快速处理（时间优先）
./hydrapress -i ./Videos --profile fast

# 极限压缩（空间优先）
./hydrapress -i ./Videos --profile maxcompress

# 自定义参数
./hydrapress -i ./Videos -o ./Compressed -c 18 -p medium --subdirs

# 仅处理特定文件
./hydrapress -i ./Videos -f "REC*.mp4"
```

---

## 工作原理

```
源目录 (Videos/)
  ├── 2024-08-01.mp4  ──→  压缩 →  ┌── 输出目录 (Videos_compressed/)
  ├── 2024-08-02.mp4  ──→  压缩 →      │   ├── 2024-08-01.mp4
  └── ...                           │   └── 2024-08-02.mp4
```

- 源文件从未被修改或删除
- 已存在的输出文件自动跳过（断点续传）
- Ctrl+C 中断 → 重跑继续未完成文件
- 以降低系统优先级运行，不干扰前台操作

---

## 故障排除

**Q: 运行一半关机了怎么办？**  
直接重新运行脚本，已压缩文件会被自动跳过，只处理未完成的。

**Q: 转码中电脑发烫/风扇狂转？**  
将 `nice` 改为 `19`（最低优先级），  
或 `PRESET` 改为 `fast`/`ultrafast`，  
或使用较快的 `profile` 。

**Q: 转码后的视频能在手机上播放吗？**  
可以。输出使用 `-tag:v hvc1` 标记，兼容 iPhone / Android / 电脑。

**Q: 为什么 `ultrafast + CRF 14` 和 `slow + CRF 18` 效果差不多？**  
x265 的 `slow` 在相同 CRF 下文件更大但质量略好（SSIM +0.004），使用 `ultrafast + 低 CRF` 可以用更少时间达到接近效果。

**Q: 如何恢复原文件？**  
源文件保留在原目录未被修改。

**Q: 输出目录与源目录相同会怎样？**  
脚本会拒绝执行（输出目录不能与源目录相同），避免静默跳过所有文件。

---

## 测试记录

| 项目 | 值 |
|------|-----|
| **机型** | MacBook Pro 15" 2015 |
| **CPU** | Intel i7-4980HQ 4 Core 8 Thread @ 2.80GHz |
| **内存** | 16 GB |
| **系统** | macOS 12.7.6 |
| **ffmpeg** | 5.1.2 |
| **源文件** | 22x MP4 (H.264 1080p), total 4.21 GB |
| **配置** | CRF=22, preset=slow, nice=10, bit=auto |
| **耗时** | 约 5 小时 |
| **输出体积** | 1.53 GB |
| **压缩率** | **63.7%** |

---

## LICENSE

MIT License - 详见 [LICENSE](LICENSE)

---

## 技术文档

- [x265 编码指南：Preset、CRF、内容类型与输出结果](x265_encoding_guide.md)
- [快速帮助](`-h`) 与 [完整说明](`--help`) 可在终端查看