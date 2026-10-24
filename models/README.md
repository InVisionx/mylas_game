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

Three rigged variants ship in the repo: `customer_a` (average), `customer_b`
(broad, belly, cap) and `customer_c` (slim, hair bun). A customer picks one at
random on spawn and falls back to the procedural body if none load.

Contract for a replacement or a new variant:

- humanoid, ~1.84 m tall, feet at origin, facing −Z
- armature bones named `Hips, Spine, Chest, Neck, Head, Shoulder.L/R,
  UpperArm.L/R, LowerArm.L/R, Hand.L/R, Thigh.L/R, Shin.L/R, Foot.L/R`
- optional `FingerExtra0.L/R` and `FingerExtra1.L/R` bones weighted to a pair of
  hidden digits — the game scales them to zero until the six-finger anomaly
  needs them, so the hand counts five fingers until it doesn't
- animations named `idle` and `walk` (looping)
- one material per body part named `Skin`, `Shirt`, `Pants`, `Hair`, `Eye`,
  `Shoe` — the game duplicates and recolours them per customer, so two people
  never look identical

Anomalies that need facial geometry (wide smile, extra teeth, offset eyes) still
only exist on the procedural body; everything skeletal (neck angle, long hands,
extra fingers, head turns, freeze, glitch, silhouette) works on the models.

Rebuild all three with:

```
blender -b --factory-startup -P tools/blender/build_customer_rig.py
```

The script is parameterised by `SPECS` at the top: torso width/depth, belly,
arm and leg thickness, head size, shoulder spread and hair style. Verify an
export without opening the game:

```
godot --headless --path . -- --modelcheck=customer_b
blender -b --factory-startup -P tools/blender/inspect_customer.py -- models/customers/customer_b.glb
```

## How models are normalised

`scripts/items/product_mesh.gd` computes the combined AABB, uniformly scales it to
fit the product's declared size, and centres it on the item origin. Shadows are
disabled on imported meshes to keep the handheld fast.
