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

`customer_man.glb` is a real rigged humanoid (Khronos `CesiumMan`, CC-BY 4.0),
re-exported from Blender with an added breathing `idle` clip alongside the
shipped `walk` cycle. `MODEL_PATHS` in `scripts/customer/customer_body.gd` lists
every model that should be considered; the first one that loads wins and anything
missing falls back to the procedural body.

The loader is deliberately tolerant, because rigs disagree about everything:

- height is normalised from the **skeleton**, not the mesh AABB (a skinned mesh
  reports bind-space bounds, which can be Z-up even when the skeleton is Y-up)
- bones are matched by pattern, not name: `Head`/`mixamorig:Head`, any `neck`,
  and the deepest hand/wrist bone per side (`Hand.R`, `LeftHand`,
  `Skeleton_arm_joint_L__4_`); digit bones are skipped so a thumb tip never
  becomes the hand anchor
- clips are matched by name (`walk`, `idle`, or `run` as a walk fallback); a
  single-clip export is crawled slowly for the idle pose
- each customer gets a per-material tint, applied as a multiply so textured
  models keep their detail

Anomalies: everything skeletal works (neck angle, long hands, head turns, freeze,
glitch, silhouette). Facial mutations (wide smile, extra teeth, offset eyes) and
six fingers need geometry the mesh does not have — they still exist as clues in
inspection text, but they have no visible deformation on this model.

Rebuild / extend:

```
# add an idle clip to a walk-only export
blender -b --factory-startup -P tools/blender/add_idle_clip.py -- in.glb out.glb
# verify what the game will actually resolve
godot --headless --path . -- --modelcheck=body
```

## How models are normalised

`scripts/items/product_mesh.gd` computes the combined AABB, uniformly scales it to
fit the product's declared size, and centres it on the item origin. Shadows are
disabled on imported meshes to keep the handheld fast.
