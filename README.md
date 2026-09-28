# MinerU Ascend CPU Offline Service

中文名称：**MinerU CPU 离线解析服务**

本仓库提供面向 Linux `aarch64/arm64` 服务器的 MinerU 3.4.5 CPU 离线服务。它把 MinerU pipeline、模型文件、完整性校验脚本和容器启动方式整理成一个可复用的部署单元，适合没有可用 NPU 或需要 CPU 兜底解析的场景。

服务只承担文档解析，不包含 MCP 转发层；如需通过 MCP 调用，请配合 `mineru-ascend-mcp-gateway` 使用。

## 能力

- MinerU `3.4.5`
- 纯 CPU pipeline
- 服务端口：容器 `8856`
- API：`/docs`、`/file_parse`
- 40 个模型文件 SHA-256 校验
- 21 项模型真实加载冒烟测试

本仓库不提交约 2.5GB 的 Docker 镜像导出包。镜像下载地址请在下方补充。

## 离线镜像下载

请将真实地址替换下面的占位符：

```text
百度网盘地址：<BAIDU_PAN_URL>
提取码：<BAIDU_PAN_CODE>
文件名：mineru-cpu-3.4.5-image.tar.gz
SHA-256：2535f8553f5e408cec4808ae6e20ac2603bf52fa2011d68f063426de8df7a189
```

下载后建议先校验：

```bash
sha256sum mineru-cpu-3.4.5-image.tar.gz
docker load < mineru-cpu-3.4.5-image.tar.gz
```

## 直接运行镜像

```bash
docker run -d \
  --name mineru-cpu \
  -p 8856:8856 \
  --restart unless-stopped \
  mineru-cpu:3.4.5
```

这是本仓库服务的标准启动容器命令。启动后，MinerU API 地址为：

```text
http://<服务器地址>:8856
```

或使用：

```bash
bash deploy/mineru-cpu-start.sh
```

## 验证 API

```bash
curl -fsS http://127.0.0.1:8856/docs

curl -fsS http://127.0.0.1:8856/file_parse \
  -F 'files=@/path/to/test.pdf' \
  -F 'backend=pipeline' \
  -F 'return_md=true'
```

必须显式指定 `backend=pipeline`。该镜像没有 VLM 大模型，不适用于需要额外 VLM 的 `hybrid-engine` 路径。

## 模型完整性检查

在运行中的容器上执行：

```bash
bash deploy/mineru-verify-models.sh mineru-cpu
docker exec mineru-cpu python /opt/mineru-verify/smoke_all_models.py
```

期望结果：

- `OK=40 MISSING=0 BAD=0`
- `21/21 通过`

验收时建议使用一份带公章的 PDF，覆盖 seal 模型路径。

## 从源码构建

构建阶段需要联网下载 Python 依赖和 ModelScope 模型，且建议在目标架构机器上原生构建：

```bash
docker build -t mineru-cpu:3.4.5 .
docker save mineru-cpu:3.4.5 | gzip > mineru-cpu-3.4.5-image.tar.gz
```

构建时会执行模型 SHA-256 校验和完整模型加载冒烟测试；任一模型缺失或加载失败都会使构建失败。

## 目录说明

```text
Dockerfile
deploy/
├── mineru-cpu-start.sh
├── mineru-verify-models.sh
├── mineru-pipeline-models-3.4.5.sha256
└── smoke_all_models.py
```

## 已验证边界

- 已验证目标：Linux `aarch64/arm64`
- 默认服务：纯 CPU pipeline
- 首次解析会有模型初始化开销
- 未承诺 x86_64、GPU 或 VLM/hybrid-engine 兼容性

## 许可证和第三方依赖

发布前请补充本仓库许可证，并确认 MinerU、模型权重、PyTorch、ModelScope 及其他依赖的再分发许可。不要把生产地址、Token、真实业务文件或内部配置提交到仓库。

公开提交前请先阅读 [PUBLISHING.md](./PUBLISHING.md)，避免提交记录暴露个人姓名或工具尾注。
