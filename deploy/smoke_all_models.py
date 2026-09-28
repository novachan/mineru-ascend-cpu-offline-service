#!/usr/bin/env python3
"""MinerU 3.4.5 pipeline 全模型加载冒烟测试。

在容器内直接用 pipeline 自身的初始化代码实例化全部原子模型：
  - Layout（PP-DocLayoutV2）
  - MFR 公式识别（unimernet_small 与 pp_formulanet_plus_m 两个变体）
  - OCR 全部 14 语言变体（含 seal / seal_lite 印章、ch_server）
  - 有线表 / 无线表识别（wired=unet.onnx / wireless=slanet-plus.onnx）
  - 表格分类（PP-LCNet_x1_0_table_cls.onnx）+ 表格方向分类（复用 OCR）

任何一个模型文件缺失或损坏都会在这里暴露（懒加载问题根治）。
用法：docker exec <容器> python3 /opt/mineru-verify/smoke_all_models.py
退出码 0 = 全部加载成功。
"""
import os
import subprocess
import sys
import time
import traceback

os.environ.setdefault("MINERU_MODEL_SOURCE", "local")

from mineru.backend.pipeline.model_init import (
    AtomModelSingleton,
    mfr_model_init,
    pp_doclayout_v2_model_init,
)
from mineru.backend.pipeline.model_list import AtomicModel
from mineru.utils.enum_class import ModelPath
from mineru.utils.models_download_utils import auto_download_and_get_model_root_path

# models_config.yml 中全部语言键（14 个，以容器内实际解析结果为准）
ALL_LANGS = [
    "ch", "ch_server", "seal", "seal_lite",
    "korean", "arabic", "cyrillic", "devanagari", "el",
    "east_slavic", "ta", "te", "th", "ka",
]

results = []


def check(name, fn):
    t0 = time.time()
    try:
        fn()
        results.append((name, True, time.time() - t0, ""))
    except Exception as exc:
        results.append((name, False, time.time() - t0, f"{type(exc).__name__}: {exc}"))


def root(rel):
    return os.path.join(auto_download_and_get_model_root_path(rel), rel)


def main():
    mgr = AtomModelSingleton()

    def load_layout():
        mgr.get_atom_model(
            atom_model_name=AtomicModel.Layout,
            pp_doclayout_v2_weights=root(ModelPath.pp_doclayout_v2),
            device="cpu",
        )

    check("Layout/PP-DocLayoutV2", load_layout)

    def load_mfr_unimernet():
        mfr_model_init(str(root(ModelPath.unimernet_small)), "cpu")

    check("MFR/unimernet_small", load_mfr_unimernet)

    def load_mfr_formulanet():
        # MFR_MODEL 在模块导入时读 MINERU_FORMULA_CH_SUPPORT 决定分支，
        # 本进程已按默认（unimernet）导入，此变体必须在子进程中加载。
        code = (
            "import os; os.environ['MINERU_MODEL_SOURCE']='local'; "
            "os.environ['MINERU_FORMULA_CH_SUPPORT']='true'; "
            "from mineru.backend.pipeline.model_init import mfr_model_init; "
            "from mineru.utils.enum_class import ModelPath; "
            "from mineru.utils.models_download_utils import auto_download_and_get_model_root_path; "
            "mfr_model_init(os.path.join("
            "auto_download_and_get_model_root_path(ModelPath.pp_formulanet_plus_m), "
            "ModelPath.pp_formulanet_plus_m), 'cpu')"
        )
        proc = subprocess.run([sys.executable, "-c", code], timeout=600)
        if proc.returncode != 0:
            raise RuntimeError(f"子进程加载失败，退出码 {proc.returncode}")

    check("MFR/pp_formulanet_plus_m", load_mfr_formulanet)

    for lang in ALL_LANGS:
        check(
            f"OCR/{lang}",
            lambda l=lang: mgr.get_atom_model(
                atom_model_name=AtomicModel.OCR,
                det_db_box_thresh=0.5,
                lang=l,
                det_db_unclip_ratio=1.6,
                enable_merge_det_boxes=False,
            ),
        )

    check(
        "Table/Wired(unet)",
        lambda: mgr.get_atom_model(
            atom_model_name=AtomicModel.WiredTable, lang="ch"
        ),
    )
    check(
        "Table/Wireless(slanet-plus)",
        lambda: mgr.get_atom_model(
            atom_model_name=AtomicModel.WirelessTable, lang="ch"
        ),
    )
    check(
        "Table/Cls(PP-LCNet)",
        lambda: mgr.get_atom_model(atom_model_name=AtomicModel.TableCls),
    )
    check(
        "Table/OrientationCls",
        lambda: mgr.get_atom_model(
            atom_model_name=AtomicModel.TableOrientationCls, lang="ch"
        ),
    )

    failed = [r for r in results if not r[1]]
    for name, ok, dur, err in results:
        mark = "OK " if ok else "FAIL"
        print(f"[{mark}] {name:<36} {dur:6.1f}s {err}")
    print(f"\n== {len(results) - len(failed)}/{len(results)} 通过 ==")
    if failed:
        print("失败模型：")
        for name, _, _, err in failed:
            print(f"  - {name}: {err}")
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        sys.exit(2)
