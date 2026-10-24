# Models

Drop real assets here and the game picks them up automatically. Anything missing
falls back to the procedural placeholder, so you can replace one object at a time.

## Products — `models/products/<id>.glb`

The id must match `data/products.json` (e.g. `milk`, `cereal`, `detergent`).

- Origin: bottom-centre, feet on `y = 0` is fine — the loader re-centres it.
- Scale: real-world metres (a milk carton is about 0.16 × 0.26 × 0.16 m). The loader
  fits the model into the size declared in `data/products.json`, so exact scale is not
  critical, but keep the proportions right.
- Facing: any; products are viewed from one side. If the label ends up facing away,
  add `"model_yaw": 180` to that product in `data/products.json` (degrees).
- Textures: embed them in the glb (GLB, not glTF+separate files).

## Customers — `models/customers/`

Two kinds of body exist and both are real rigged characters:

| File | Source |
|---|---|
| `customer_man.glb` | Khronos `CesiumMan` (CC-BY 4.0), re-exported with an added `idle` clip |
| `customer_gen_*.glb` | generated in Invision Studio: FLUX image → Hunyuan 2.1 mesh → UltraTex, then rigged here |

A customer picks one at random (see `MODEL_PATHS` in
`scripts/customer/customer_body.gd`), gets tinted slightly, and is scaled from
1.62 m to 1.9 m. Anything missing falls back to the procedural body.

### Making a new generated customer

Generation is four steps; only the first two cost GPU time (~5 and ~4 min):

```
1. Invision: generate_mesh(prompt="full body studio photo of a person standing,
   arms slightly away from the body, plain white background", backend=hunyuan21)
2. Invision: texture_mesh(mesh=<job>/output/model.glb, backend=ultratex)
3. blender -b --factory-startup -P tools/blender/rig_generated.py -- \
       <job>/output/model.glb models/customers/customer_gen_X.glb
4. add the file to MODEL_PATHS, and check its facing (below)
```

`rig_generated.py` normalises the mesh to 1.8 m with feet on the ground, builds a
19-bone humanoid scaled to the body, skins it (automatic weights, falling back to
nearest-bone — Blender's heat weighting frequently declines generated topology),
applies the shared `idle`/`walk` clips from `rig_anim.py`, and downscales the
atlas to 512 px so each character costs ~2.4 MB instead of ~5.

### Checking a new character without eyes on it

Exports disagree about which way "forward" is, and getting it wrong makes people
moonwalk. Render four sides and ask a vision model which shows the face:

```
godot --path . --resolution 600x800 -- --modelshot="C:/shots" --noground \
    --model=res://models/customers/customer_gen_X.glb
mesh_gen\.venv\Scripts\python.exe tools\vision\see.py \
    --image C:/shots/model_view_00.png --question "front of a person, or back?"
```

`model_view_00` is the camera at +Z. If it reports "front", the mesh faces +Z and
needs `180.0` in the `MODEL_YAW` table. `contact.png` in the same folder stitches
all four views together.

### Rigid-limitation worth knowing

Nearest-bone skinning is rigid at the joints: elbows and knees bend as blocks, not
with soft creases. For this art style at this camera distance that reads fine, but
it is why the generated bodies do not deform like a hand-weighted hero character.

## Anomalies the models can express

Skeletal ones work: neck angle, long hands (bone scale), head turns, freeze,
glitch, silhouette. Facial mutations (wide smile, extra teeth, offset eyes) and a
literal sixth finger need geometry the meshes do not have — those clues remain in
the inspection text only.

## How models are normalised

`scripts/items/product_mesh.gd` computes the combined AABB, uniformly scales it to
fit the product's declared size, and centres it on the item origin. Shadows are
disabled on imported meshes to keep the handheld fast.
