#!/usr/bin/env python3
"""Convert NudeNet's 320n detector (ONNX, AGPL-3.0) to Core ML for Lookout.

    python3 -I tools/convert_model.py path/to/320n.onnx mac/assets/NudeNet320n.mlpackage

Needs: pip install coremltools onnx onnx2torch torch onnxruntime numpy
The 320n.onnx file ships inside the `nudenet` Python package (v3.4).

The Core ML model takes a 320 x 320 RGB image and scales it to 0..1 itself,
as NudeNet's preprocessing does, and returns `detections`, shape
[1, 22, 2100]: box centre x, y, width, height, then 18 label scores, for 2100
candidate boxes. mac/Sources/LookoutCore/Decode.swift turns that into hits.
After converting, the script checks the Core ML output against onnxruntime.
"""

import sys

import coremltools as ct
import numpy as np
import onnx
import onnxruntime as ort
import torch
from onnx2torch import convert


def main(src, dst):
    net = convert(onnx.load(src)).eval()
    example = torch.rand(1, 3, 320, 320)
    traced = torch.jit.trace(net, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=(1, 3, 320, 320), scale=1 / 255.0,
                             color_layout=ct.colorlayout.RGB)],
        outputs=[ct.TensorType(name="detections")],
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )
    mlmodel.short_description = "NudeNet 320n detector (github.com/notAI-tech/NudeNet, AGPL-3.0), converted for Lookout"
    mlmodel.license = "AGPL-3.0"
    mlmodel.save(dst)

    # Same picture through both: Core ML must match onnxruntime closely.
    from PIL import Image
    rng = np.random.default_rng(0)
    rgb = (rng.random((320, 320, 3)) * 255).astype(np.uint8)
    rgb[80:240, 80:240] = [220, 170, 140]  # a skin-coloured square, to get some scores
    sess = ort.InferenceSession(src, providers=["CPUExecutionProvider"])
    ref = sess.run(None, {sess.get_inputs()[0].name: (rgb.transpose(2, 0, 1)[None] / 255.0).astype(np.float32)})[0]
    got = ct.models.MLModel(dst).predict({"image": Image.fromarray(rgb)})["detections"]
    print("shape", got.shape, "reference", ref.shape)
    boxes, scores = np.abs(got[:, :4] - ref[:, :4]), np.abs(got[:, 4:] - ref[:, 4:])
    print(f"box error: mean {boxes.mean():.3f} px, max {boxes.max():.3f} px")
    print(f"score error: mean {scores.mean():.5f}, max {scores.max():.5f}")
    assert got.shape == ref.shape and scores.max() < 0.02, "Core ML output differs from onnxruntime"
    print("OK:", dst)


if __name__ == "__main__":
    main(*sys.argv[1:3])
