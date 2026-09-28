#!/usr/bin/env bash
# ============================================================================
# MinerU 3.4.5 pipeline 模型完整性校验脚本（离线环境可用，只依赖 bash + coreutils）
#
# 用途：在部署了 mineru-cpu 容器的服务器上一次性校验模型目录是否完整，
#       避免"缺 seal 模型 → 带公章 PDF 解析 409"这类懒加载缺失问题。
#
# 清单来源：本仓库 deploy/mineru-pipeline-models-3.4.5.sha256（40 个文件，2.5GB），
#          由已验证可用的镜像 mineru-cpu:3.4.5（sha256:baf7e7a8ae95）生成，
#          覆盖 MinerU 3.4.5 官方下载清单全部 7 类模型 + 14 语言 OCR 权重。
#
# 用法（在离线服务器上，脚本与 .sha256 清单放同一目录）：
#   bash mineru-verify-models.sh                     # 校验运行中的 mineru-cpu 容器
#   bash mineru-verify-models.sh <容器名>            # 校验指定容器
#   bash mineru-verify-models.sh --path /dir         # 校验宿主机上的模型目录
#
# 判定：
#   - 全部 OK       -> 退出码 0，模型完整，带章/无章文档均可解析
#   - 有 MISSING/BAD -> 退出码 1，按报告补齐或整体替换目录，不要逐个猜
# ============================================================================
set -euo pipefail

CONTAINER="${1:-mineru-cpu}"
MANIFEST="$(cd "$(dirname "$0")" && pwd)/mineru-pipeline-models-3.4.5.sha256"
[ -f "$MANIFEST" ] || { echo "错误：找不到清单 ${MANIFEST}（需与脚本同目录）"; exit 2; }

# 容器内模型根目录（mineru.json 中 models-dir.pipeline 的值）
MODEL_ROOT_IN_CONTAINER="/root/.cache/modelscope/models/OpenDataLab--PDF-Extract-Kit-1.0/snapshots/master"

if [ "$CONTAINER" = "--path" ]; then
  MODEL_ROOT="$2"
  RUN() { command "$@"; }
else
  docker inspect "$CONTAINER" >/dev/null 2>&1 || { echo "错误：容器 $CONTAINER 不存在"; exit 2; }
  MODEL_ROOT="$MODEL_ROOT_IN_CONTAINER"
  RUN() { docker exec "$CONTAINER" "$@"; }
fi

echo "== MinerU 3.4.5 pipeline 模型完整性校验 =="
echo "目标：${CONTAINER} 的 $MODEL_ROOT"
echo "清单：${MANIFEST}（$(wc -l < "$MANIFEST") 个文件）"
echo

missing=0; bad=0; ok=0
while read -r expected_hash rel_path; do
  [ -n "$expected_hash" ] || continue
  if ! RUN test -f "$MODEL_ROOT/$rel_path"; then
    echo "MISSING  $rel_path"
    missing=$((missing+1))
    continue
  fi
  actual_hash="$(RUN sha256sum "$MODEL_ROOT/$rel_path" | cut -d' ' -f1)"
  if [ "$actual_hash" = "$expected_hash" ]; then
    ok=$((ok+1))
  else
    echo "BAD      $rel_path"
    echo "         期望 $expected_hash"
    echo "         实际 $actual_hash"
    bad=$((bad+1))
  fi
done < "$MANIFEST"

echo
echo "== 结果：OK=$ok  MISSING=$missing  BAD=$bad =="
if [ "$missing" -eq 0 ] && [ "$bad" -eq 0 ]; then
  echo "✅ 模型完整。pipeline 全路径（Layout/MFD/MFR/OCR 14 语言/Seal/TabRec/TabCls）模型齐备。"
  exit 0
else
  echo "❌ 模型不完整。缺 $missing 个、损坏 $bad 个。"
  echo "   修复：优先整目录替换（从已验证镜像导出，见部署手册）；"
  echo "   临时补文件也必须按本清单核对 sha256，且容器重建后会丢失。"
  exit 1
fi
