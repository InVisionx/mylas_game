"""Add a breathing idle clip to a rigged customer that only shipped a walk cycle.

The imported walk action is kept (fake user) and both actions are exported, so the
result has `walk` + `idle` and the game can cross-fade between them.

Usage: blender -b --factory-startup -P add_idle_clip.py -- <in.glb> <out.glb>
"""
import math
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
src = argv[0]
dst = argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH')

# Keep whatever clips the file already had (the walk cycle lives here).
for action in bpy.data.actions:
    action.use_fake_user = True
    if "walk" not in action.name.lower() and action.name.lower().startswith(("anim", "armature")):
        # Give the shipped locomotion clip a name the game can recognise.
        print("RENAMED %s -> walk" % action.name)
        action.name = "walk"
    print("IMPORTED ACTION", action.name, "frames", action.frame_range[:])

for pose_bone in rig.pose.bones:
    pose_bone.rotation_mode = 'QUATERNION'

rig.animation_data_create()
idle = bpy.data.actions.new("idle")
rig.animation_data.action = idle

FRAMES = 96  # 4 s at 24 fps
BREATH = ["Skeleton_torso_joint_2", "torso_joint_3"]
HEAD = [b.name for b in rig.pose.bones if "neck" in b.name.lower()]
ARMS = [b.name for b in rig.pose.bones if "arm_joint" in b.name.lower()]


def key(name, frame, rot):
    bone = rig.pose.bones.get(name)
    if bone is None:
        return
    bone.rotation_quaternion = rot
    bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def rot(axis, degrees):
    half = math.radians(degrees) * 0.5
    return {
        "x": (math.sin(half), 0.0, 0.0, math.cos(half)),
        "z": (0.0, 0.0, math.sin(half), math.cos(half)),
    }[axis]


for step in range(5):
    frame = 1 + step * (FRAMES // 4)
    phase = math.sin(step * math.pi * 0.5)          # 0, 1, 0, -1, 0
    sway = math.sin(step * math.pi * 0.25)          # gentler, offset rhythm
    for name in BREATH:
        key(name, frame, rot("x", 1.6 * phase))
    for name in HEAD:
        key(name, frame, rot("z", 1.8 * sway))
    for index, name in enumerate(ARMS):
        side = -1.0 if "R" in name.upper() else 1.0
        key(name, frame, rot("x", 1.4 * phase * side))

rig.animation_data.action = None
for action in bpy.data.actions:
    action.use_fake_user = True

bpy.ops.object.select_all(action='DESELECT')
rig.select_set(True)
mesh.select_set(True)
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
print("EXPORTED %s %d bytes, actions=%s" % (
    dst, os.path.getsize(dst), [a.name for a in bpy.data.actions]))
