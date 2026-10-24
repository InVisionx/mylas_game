"""Print where a rigged customer's key vertex groups sit, so geometry can be
verified without looking at a render.

Usage: blender -b --factory-startup -P inspect_customer.py -- <glb>
"""
import sys

import bpy

path = sys.argv[sys.argv.index("--") + 1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=path)

mesh = next(o for o in bpy.data.objects if o.type == 'MESH')
print("BOUNDS size=(%.3f, %.3f, %.3f) verts=%d polys=%d" % (
    mesh.dimensions.x, mesh.dimensions.y, mesh.dimensions.z,
    len(mesh.data.vertices), len(mesh.data.polygons)))

wanted = ("Hand.R", "Hand.L", "Head", "FingerExtra0.R", "FingerExtra1.R",
          "FingerExtra0.L", "FingerExtra1.L")
for group in mesh.vertex_groups:
    if group.name not in wanted:
        continue
    points = [v.co for v in mesh.data.vertices
              if any(g.group == group.index and g.weight > 0.5 for g in v.groups)]
    if not points:
        print("GROUP %s EMPTY" % group.name)
        continue
    xs = [p.x for p in points]
    ys = [p.y for p in points]
    zs = [p.z for p in points]
    print("GROUP %-15s n=%3d x=%6.3f..%6.3f y=%6.3f..%6.3f z=%6.3f..%6.3f" % (
        group.name, len(points), min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
