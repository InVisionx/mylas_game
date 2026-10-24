"""Rig a generated (static) customer mesh and give it the shared idle/walk clips.

Invision/Hunyuan output is a textured mesh with no skeleton, so this builds one:
a standard humanoid scaled to the mesh, automatic weights where Blender can solve
them, nearest-bone fallback where it cannot, then the same animations the
hand-built rig uses.

Usage:
  blender -b --factory-startup -P rig_generated.py -- in.glb out.glb [yaw_degrees]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import rig_anim  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
yaw = float(argv[2]) if len(argv) > 2 else 0.0

HEIGHT = 1.8

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)


def all_meshes():
    return [o for o in bpy.data.objects if o.type == 'MESH']


meshes = all_meshes()
if not meshes:
    raise SystemExit("no mesh in %s" % src)

if len(meshes) > 1:
    bpy.ops.object.select_all(action='DESELECT')
    for item in meshes:
        item.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()

body = all_meshes()[0]
bpy.context.view_layer.objects.active = body
body.name = "CustomerBody"
body.data.name = "CustomerBodyMesh"

# A 1024 atlas per character costs several MB in the APK for no visible gain at
# the distances this game is played from.
for image in bpy.data.images:
    if image.size[0] > 512 or image.size[1] > 512:
        image.scale(512, 512)
        print("TEXTURE %s -> %dx%d" % (image.name, image.size[0], image.size[1]))

if yaw:
    body.rotation_euler = (0.0, 0.0, math.radians(yaw))
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)

# --- normalise: 1.8 m tall, feet on z = 0 -----------------------------------
coords = [body.matrix_world @ v.co for v in body.data.vertices]
min_z = min(c.z for c in coords)
max_z = max(c.z for c in coords)
scale = HEIGHT / max(max_z - min_z, 0.001)
body.scale = (scale, scale, scale)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

coords = [body.matrix_world @ v.co for v in body.data.vertices]
body.location.z -= min(c.z for c in coords)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

coords = [body.matrix_world @ v.co for v in body.data.vertices]
print("MESH verts=%d tris=%d height=%.3f" % (
    len(body.data.vertices),
    sum(len(p.vertices) - 2 for p in body.data.polygons),
    max(c.z for c in coords) - min(c.z for c in coords)))
print("MESH width x %.3f..%.3f depth y %.3f..%.3f" % (
    min(c.x for c in coords), max(c.x for c in coords),
    min(c.y for c in coords), max(c.y for c in coords)))

H = HEIGHT
band = [c for c in coords if 0.45 * H <= c.z <= 0.55 * H]
ctr_y = (min(c.y for c in band) + max(c.y for c in band)) * 0.5 if band else 0.0

bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
rig = bpy.context.object
rig.name = "CustomerRig"
rig.data.name = "CustomerArmature"
edit_bones = rig.data.edit_bones
for existing in list(edit_bones):
    edit_bones.remove(existing)


def bone(name, head, tail, parent=None, connect=False):
    created = edit_bones.new(name)
    created.head = Vector(head)
    created.tail = Vector(tail)
    if parent:
        created.parent = edit_bones[parent]
        created.use_connect = connect
    return created


bone("Hips", (0, ctr_y, 0.53 * H), (0, ctr_y, 0.60 * H))
bone("Spine", (0, ctr_y, 0.60 * H), (0, ctr_y, 0.72 * H), "Hips", True)
bone("Chest", (0, ctr_y, 0.72 * H), (0, ctr_y, 0.82 * H), "Spine", True)
bone("Neck", (0, ctr_y, 0.82 * H), (0, ctr_y, 0.87 * H), "Chest", True)
bone("Head", (0, ctr_y, 0.87 * H), (0, ctr_y, 0.99 * H), "Neck", True)
for side in (1, -1):
    tag = "L" if side > 0 else "R"
    bone("Shoulder." + tag, (0.045 * H * side, ctr_y, 0.80 * H),
         (0.11 * H * side, ctr_y, 0.80 * H), "Chest")
    bone("UpperArm." + tag, (0.11 * H * side, ctr_y, 0.80 * H),
         (0.115 * H * side, ctr_y, 0.62 * H), "Shoulder." + tag, True)
    bone("LowerArm." + tag, (0.115 * H * side, ctr_y, 0.62 * H),
         (0.115 * H * side, ctr_y, 0.47 * H), "UpperArm." + tag, True)
    bone("Hand." + tag, (0.115 * H * side, ctr_y, 0.47 * H),
         (0.115 * H * side, ctr_y, 0.42 * H), "LowerArm." + tag, True)
    bone("Thigh." + tag, (0.06 * H * side, ctr_y, 0.52 * H),
         (0.06 * H * side, ctr_y, 0.28 * H), "Hips")
    bone("Shin." + tag, (0.06 * H * side, ctr_y, 0.28 * H),
         (0.06 * H * side, ctr_y, 0.05 * H), "Thigh." + tag, True)
    bone("Foot." + tag, (0.06 * H * side, ctr_y, 0.05 * H),
         (0.06 * H * side, ctr_y + 0.07 * H, 0.01 * H), "Shin." + tag, True)

bpy.ops.object.mode_set(mode='OBJECT')
print("RIG bones=%d" % len(rig.data.bones))

# --- skinning ---------------------------------------------------------------
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
try:
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    print("SKIN automatic weights")
except RuntimeError as exc:
    print("SKIN automatic weights failed: %s" % exc)

weighted = sum(1 for v in body.data.vertices if len(v.groups) > 0)
if weighted < len(body.data.vertices) * 0.9:
    print("SKIN fallback to nearest-bone (%d/%d weighted)" % (
        weighted, len(body.data.vertices)))
    for group in list(body.vertex_groups):
        body.vertex_groups.remove(group)
    segments = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones]
    groups = {name: body.vertex_groups.new(name=name) for name, _, _ in segments}

    def dist_to_segment(point, a, b):
        ab = b - a
        denom = ab.length_squared
        if denom < 1e-9:
            return (point - a).length
        t = max(0.0, min(1.0, (point - a).dot(ab) / denom))
        return (point - (a + ab * t)).length

    for vert in body.data.vertices:
        ranked = sorted((dist_to_segment(vert.co, a, b), name) for name, a, b in segments)
        best_d, best_name = ranked[0]
        second_d, second_name = ranked[1]
        if second_d <= best_d * 1.6 + 0.02:
            w1 = 1.0 / (best_d * best_d + 1e-5)
            w2 = 1.0 / (second_d * second_d + 1e-5)
            total = w1 + w2
            groups[best_name].add([vert.index], w1 / total, 'REPLACE')
            groups[second_name].add([vert.index], w2 / total, 'REPLACE')
        else:
            groups[best_name].add([vert.index], 1.0, 'REPLACE')
    if body.parent != rig:
        body.parent = rig
        modifier = body.modifiers.new("Armature", 'ARMATURE')
        modifier.object = rig

weighted = sum(1 for v in body.data.vertices if len(v.groups) > 0)
print("SKIN weighted=%d/%d groups=%d" % (
    weighted, len(body.data.vertices), len(body.vertex_groups)))

rig_anim.build_actions(rig)
rig.animation_data.action = None

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=dst,
    export_format='GLB',
    use_selection=True,
    export_skins=True,
    export_animations=True,
    export_animation_mode='ACTIONS',
    export_yup=True,
)
print("EXPORTED %s %d bytes" % (dst, os.path.getsize(dst)))


