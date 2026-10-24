# Vision tools

The coding agent working on this project cannot receive images — MCP image blocks
arrive as base64 text and `read_files` refuses them ("current model does not
support image input"). So screenshots are turned into text two ways.

## 1. A local vision model — `tools/vision/see.py`

Describes or answers questions about a PNG. Runs on the torch environment that
Invision Studio already ships, so nothing has to be installed:

```
C:\Users\mattm\Desktop\mesh_gen\.venv\Scripts\python.exe tools\vision\see.py ^
    --image build\shots\model_idle_00.png ^
    --question "Is there a person in this image? Describe their pose."
```

- Default model: `HuggingFaceTB/SmolVLM-500M-Instruct` (~1 GB, downloads on first run)
- Better detail: add `--model=HuggingFaceTB/SmolVLM2-2.2B-Instruct` (~4.5 GB) — the
  500 M model is fast but vague, and said "blocky shape" about a human silhouette
- Fits comfortably on the 16 GB RTX 3080 in this machine

## 2. Screenshots — `--modelshot` and `--shot`

```
# isolated character render: 3 angles, a portrait, and a walk frame (windowed only)
godot --path . --resolution 600x800 -- --modelshot="C:/shots" --noground

# the real game: wide shot, then framed on the nearest customer
godot --path . -- --night=1 --shot="C:/shots"
```

`--modelshot` prints the resolved model, mesh count and clip, and accepts
`--model=res://...` to render any single glb for comparison.

## 3. Reading a silhouette numerically

Small vision models are unreliable at "does this look right", but the silhouette
is measurable. With a black background (`--noground`) the figure's ink can be
profiled directly:

```python
from PIL import Image
im = Image.open("build/shots/model_idle_00.png").convert("L")
w, h = im.size; px = im.load()
rows = [(y, [x for x in range(w) if px[x, y] > 60]) for y in range(h)]
rows = [(y, xs) for y, xs in rows if xs]
height = rows[-1][0] - rows[0][0] + 1
width = max(max(xs) - min(xs) + 1 for _, xs in rows)
print("height/width ratio:", round(height / width, 2))
```

A person standing with arms at their sides is about 3.5-4.0. 2.3-2.7 means the
arms are held away from the body (an A-pose), which usually means the rest pose
is showing instead of a real idle.
