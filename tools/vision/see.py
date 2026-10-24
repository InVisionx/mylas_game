"""Describe or answer questions about a PNG using a small local vision model.

This exists because the coding agent driving this project cannot accept image
input directly: it can only read text. Rather than guessing what a render looks
like, screenshots are passed through this tool and turned into words.

Runs on the torch environment that already ships with Invision Studio:

  C:\\Users\\mattm\\Desktop\\mesh_gen\\.venv\\Scripts\\python.exe tools\\vision\\see.py ^
      --image shot.png --question "Is the person standing on the floor?"

First run downloads ~1 GB of weights into the HuggingFace cache.
"""
import argparse
import os
import sys

DEFAULT_MODEL = "HuggingFaceTB/SmolVLM-500M-Instruct"
# Bigger, better at detail, still fits comfortably in 16 GB:
#   HuggingFaceTB/SmolVLM2-2.2B-Instruct


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="PNG or JPG to look at")
    parser.add_argument("--question", default="Describe this image in detail.")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--max-tokens", type=int, default=220)
    args = parser.parse_args()

    if not os.path.exists(args.image):
        print("missing image: %s" % args.image, file=sys.stderr)
        return 2

    import torch
    from PIL import Image
    from transformers import AutoModelForVision2Seq, AutoProcessor

    device = "cuda" if torch.cuda.is_available() else "cpu"
    dtype = torch.bfloat16 if device == "cuda" else torch.float32

    processor = AutoProcessor.from_pretrained(args.model)
    model = AutoModelForVision2Seq.from_pretrained(
        args.model, torch_dtype=dtype, _attn_implementation="eager"
    ).to(device)
    model.eval()

    image = Image.open(args.image).convert("RGB")
    messages = [{
        "role": "user",
        "content": [{"type": "image"}, {"type": "text", "text": args.question}],
    }]
    prompt = processor.apply_chat_template(messages, add_generation_prompt=True)
    inputs = processor(text=prompt, images=[image], return_tensors="pt").to(device)

    with torch.no_grad():
        output = model.generate(**inputs, max_new_tokens=args.max_tokens, do_sample=False)

    generated = output[:, inputs["input_ids"].shape[1]:]
    text = processor.batch_decode(generated, skip_special_tokens=True)[0]
    print(text.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
