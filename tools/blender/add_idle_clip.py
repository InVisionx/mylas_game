"""Add a breathing idle clip to a rigged customer that only shipped a walk cycle.

The imported walk action is kept (fake user) and both actions are exported, so the
result has `walk` + `idle` and the game can cross-fade between them.

Usage: blender -b --factory-startup -P add_idle_clip.py -- <in.glb> <out.glb>
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

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
# Re-running this over an already-processed file would otherwise leave the old
# idle behind and export both, so drop any previous idle first.
for action in list(bpy.data.actions):
    if action.name.lower().startswith("idle"):
        print("REMOVED old action", action.name)
        bpy.data.actions.remove(action)
idle = bpy.data.actions.new("idle")
rig.animation_data.action = idle

FRAMES = 96  # 4 s at 24 fps
BREATH = [b.name for b in rig.pose.bones if "torso_joint" in b.name.lower()]
HEAD = [b.name for b in rig.pose.bones if "neck" in b.name.lower()]
ARMS = [b.name for b in rig.pose.bones if "arm_joint" in b.name.lower()]


def arm_chain(side_letter):
    """Arm bones for one side, ordered shoulder -> hand."""
    bones = [b for b in rig.pose.bones if "arm_joint" in b.name.lower()
             and ("_%s" % side_letter) in b.name.upper()]
    bones.sort(key=lambda b: len(b.parent_recursive))
    return [b.name for b in bones]


CHAINS = [arm_chain("L"), arm_chain("R")]


def aim(name, target_dir):
    """Rotate a bone about its head so it points along target_dir (armature space)."""
    pb = rig.pose.bones.get(name)
    if pb is None:
        return
    current = (pb.tail - pb.head).normalized()
    delta = current.rotation_difference(target_dir.normalized())
    head = pb.head.copy()
    pb.matrix = (Matrix.Translation(head) @ delta.to_matrix().to_4x4()
                 @ Matrix.Translation(-head) @ pb.matrix)
    bpy.context.view_layer.update()


# A rest pose with arms held out reads as a mannequin. Bring each arm down and
# slightly away from the body, and bend the elbow a touch, before keying anything.
for chain in CHAINS:
    if not chain:
        continue
    side = 1.0 if "_L" in chain[0].upper() else -1.0
    aim(chain[0], Vector((0.22 * side, 0.02, -1.0)))
    if len(chain) > 1:
        aim(chain[1], Vector((0.14 * side, -0.16, -1.0)))
    if len(chain) > 2:
        aim(chain[2], Vector((0.10 * side, -0.24, -1.0)))

base = {}
for chain in CHAINS:
    for name in chain:
        pb = rig.pose.bones.get(name)
        if pb is not None:
            base[name] = pb.rotation_quaternion.copy()


def key(name, frame, extra_rot=None):
    bone = rig.pose.bones.get(name)
    if bone is None:
        return
    bone.rotation_quaternion = base.get(name, Quaternion()).copy()
    if extra_rot is not None:
        bone.rotation_quaternion = bone.rotation_quaternion @ extra_rot
    bone.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def rot(axis, degrees):
    half = math.radians(degrees) * 0.5
    return {
        "x": Quaternion((math.sin(half), 0.0, 0.0, math.cos(half))),
        "z": Quaternion((0.0, 0.0, math.sin(half), math.cos(half))),
    }[axis]


for step in range(5):
    frame = 1 + step * (FRAMES // 4)
    phase = math.sin(step * math.pi * 0.5)          # 0, 1, 0, -1, 0
    sway = math.sin(step * math.pi * 0.25)          # gentler, offset rhythm
    for name in BREATH:
        key(name, frame, rot("x", 1.6 * phase))
    for name in HEAD:
        key(name, frame, rot("z", 1.8 * sway))
    for chain in CHAINS:
        for depth, name in enumerate(chain):
            # Arms keep their posed-down base and only breathe a little.
            key(name, frame, rot("x", (1.1 - 0.2 * depth) * phase))

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
