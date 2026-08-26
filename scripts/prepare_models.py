#!/usr/bin/env python3
"""
辅助把 ONNX 人脸模型转换为 NCNN 格式（供 Flutter 端侧推理使用）。

前置：
    pip install onnxsim
    # onnx2ncnn 来自 ncnn 构建（https://github.com/Tencent/ncnn），需加入 PATH

用法：
    python prepare_models.py --input inswapper_128.onnx --out ./models
    python prepare_models.py --input scrfd_10g.onnx      --out ./models
    python prepare_models.py --input w600k_r50.onnx      --out ./models

生成的 <name>.param / <name>.bin 放到：
    android/app/src/main/assets/
    ios/Runner/  (Copy Bundle Resources)
"""
import argparse
import os
import shutil
import subprocess
import sys


def run(cmd):
    print("> " + " ".join(cmd))
    subprocess.run(cmd, check=True)


def find_onnx2ncnn():
    p = shutil.which("onnx2ncnn")
    if p:
        return p
    # 常见本地构建路径
    candidates = [
        "ncnn/build/tools/onnx/onnx2ncnn",
        os.path.expanduser("~/ncnn/build/tools/onnx/onnx2ncnn"),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    sys.exit("找不到 onnx2ncnn，请先构建 ncnn 并将其加入 PATH。")


def convert(input_onnx: str, out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(input_onnx))[0]
    sim = os.path.join(out_dir, base + ".sim.onnx")

    # 1) onnxsim 简化
    run(["python", "-m", "onnxsim", input_onnx, sim])

    # 2) onnx -> ncnn
    onnx2ncnn = find_onnx2ncnn()
    param = os.path.join(out_dir, base + ".param")
    binf = os.path.join(out_dir, base + ".bin")
    run([onnx2ncnn, sim, param, binf])

    print(f"\n完成：\n  {param}\n  {binf}\n请把这两个文件放进 Android assets / iOS Runner 资源。")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True, help="输入 ONNX 模型路径")
    ap.add_argument("--out", default="./models", help="输出目录")
    args = ap.parse_args()
    convert(args.input, args.out)


if __name__ == "__main__":
    main()
