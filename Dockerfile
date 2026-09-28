# ============================================================================
# MinerU 3.4.5 CPU 版镜像（linux/arm64）
#
# 用途：在 aarch64 服务器（如 node4）上以纯 CPU 跑 mineru-api（/file_parse 协议），
#       对接 mineruproxy（MINERU_UPSTREAM_URL 指向本容器 8856 端口）。
#
# 依赖版本复刻自本地已验证可用的 CPU 环境（/root/mineru-cpu，MinerU 3.4.5）：
#   mineru 3.4.5 | torch 2.14.0+cpu | torchvision 0.29.0 | transformers 4.57.x
#   onnxruntime 1.30 | fastapi 0.141.1 | uvicorn 0.52.4
# 注：arm64 平台 PyPI 的 torch wheel 天然为 CPU-only（CUDA 版只有 x86_64），
#     无需 pytorch CPU 专用源。
#
# 构建（在 aarch64 机器上原生构建）：
#   docker build -t mineru-cpu:3.4.5 .
#
# 运行：
#   docker run -d --name mineru-cpu --network=host --restart unless-stopped \
#       mineru-cpu:3.4.5
#
# 验证：
#   curl http://127.0.0.1:8856/docs
#   curl http://127.0.0.1:8856/file_parse -F "files=@test.pdf" \
#       -F "backend=pipeline" -F "return_md=true"
# ============================================================================
FROM python:3.12-slim-bookworm

# opencv / onnxruntime / torch 所需的运行时系统库
RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# PyTorch 使用官方 CPU wheel 源，避免安装 NVIDIA/CUDA 运行时依赖
RUN pip install --no-cache-dir \
        torch torchvision \
        --index-url https://download.pytorch.org/whl/cpu

# 其余 Python 依赖使用清华源
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
        "mineru[pipeline]==3.4.5" \
        "fastapi==0.141.1" "uvicorn==0.52.4"

# 构建期从 modelscope（国内可达）下载 pipeline 模型集（约 2.5GB，40 个文件），
# 模型与 ~/mineru.json 配置随镜像分发，运行时零下载
RUN mineru-models-download -s modelscope -m pipeline

# six：mineru 内置 pytorchocr 运行时 import（operators.py），但 mineru 依赖声明缺失，
#      不显式安装时新构建的 pip 解析不再顺带装入（构建期冒烟关卡曾实际抓到该回归）
RUN pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple "six"

# 完整性关卡 1：按权威 sha256 清单校验全部 40 个模型文件（缺一即构建失败）。
# 清单来自已验证镜像（baf7e7a8ae95），覆盖 pipeline 全路径：
# Layout / MFR 双变体 / OCR 14 语言（含 seal 印章）/ 表格 ONNX 3 件
COPY deploy/mineru-pipeline-models-3.4.5.sha256 /tmp/mineru-pipeline-models-3.4.5.sha256
RUN MODEL_ROOT=/root/.cache/modelscope/models/OpenDataLab--PDF-Extract-Kit-1.0/snapshots/master \
    && while read -r expected rel; do \
        [ -n "$expected" ] || continue; \
        actual=$(sha256sum "$MODEL_ROOT/$rel" | cut -d' ' -f1); \
        [ "$actual" = "$expected" ] || { echo "模型校验失败: $rel"; exit 1; }; \
    done < /tmp/mineru-pipeline-models-3.4.5.sha256 \
    && echo "40 个模型文件 sha256 全部通过" \
    && rm /tmp/mineru-pipeline-models-3.4.5.sha256

# 完整性关卡 2：全模型真实加载冒烟（21 项：Layout + MFR 双变体 + OCR 14 语言 +
# 4 表格模型），杜绝"文件在但损坏/懒加载缺失"（如带公章 PDF 触发的 seal 409）
COPY deploy/smoke_all_models.py /opt/mineru-verify/smoke_all_models.py
RUN MINERU_MODEL_SOURCE=local python /opt/mineru-verify/smoke_all_models.py

ENV MINERU_MODEL_SOURCE=local
EXPOSE 8856
CMD ["mineru-api", "--host", "0.0.0.0", "--port", "8856"]
