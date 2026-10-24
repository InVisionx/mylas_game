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

Not wired yet. The procedural rig is the only thing that supports the anomaly
mutations (six fingers, wide smile, offset eyes, extra teeth). If you want real
people, the contract will be:

- humanoid, ~1.8 m tall, feet at origin, facing −Z
- empty marker nodes named `Head`, `Neck`, `RightHand`, `LeftHand`, `Eyes`
- optional animations named `idle` and `walk`

With an unrigged image-to-3D mesh the code animation disappears, and anomalies
that deform the body cannot be applied, so this needs a properly rigged character
rather than a single static mesh. Say the word and I will wire the loader to that
contract and test it against your first export.

## How models are normalised

`scripts/items/product_mesh.gd` computes the combined AABB, uniformly scales it to
fit the product's declared size, and centres it on the item origin. Shadows are
disabled on imported meshes to keep the handheld fast.
