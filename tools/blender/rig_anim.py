"""Idle and walk actions shared by every customer rig we build.

Kept separate from any particular body so a generated mesh can reuse exactly the
same motion as the hand-built one. Angles are degrees, keyed on XYZ euler, 24 fps.
"""
import math

import bpy

IDLE = [
    (1, {"Chest": {"rot": (0, 0, 0)}, "Head": {"rot": (0, 0, 0)},
         "UpperArm.L": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (0, 0, 0)},
         "Hips": {"loc": (0, 0, 0)}}),
    (18, {"Chest": {"rot": (2.4, 0, 0.9)}, "Head": {"rot": (-1.4, 0, 2.2)},
          "UpperArm.L": {"rot": (0, 0, 1.8)}, "UpperArm.R": {"rot": (0, 0, -1.8)},
          "Hips": {"loc": (0, 0, 0.004)}}),
    (36, {"Chest": {"rot": (0, 0, 0)}, "Head": {"rot": (0, 0, 0)},
          "UpperArm.L": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (0, 0, 0)},
          "Hips": {"loc": (0, 0, 0)}}),
    (54, {"Chest": {"rot": (1.4, 0, -0.9)}, "Head": {"rot": (-1.0, 0, -2.2)},
          "UpperArm.L": {"rot": (0, 0, -1.2)}, "UpperArm.R": {"rot": (0, 0, 1.2)},
          "Hips": {"loc": (0, 0, 0.002)}}),
    (72, {"Chest": {"rot": (0, 0, 0)}, "Head": {"rot": (0, 0, 0)},
          "UpperArm.L": {"rot": (0, 0, 0)}, "UpperArm.R": {"rot": (0, 0, 0)},
          "Hips": {"loc": (0, 0, 0)}}),
]

WALK = [
    (1, {"Thigh.L": {"rot": (26, 0, 0)}, "Thigh.R": {"rot": (-26, 0, 0)},
         "Shin.L": {"rot": (-6, 0, 0)}, "Shin.R": {"rot": (-34, 0, 0)},
         "UpperArm.L": {"rot": (-18, 0, 0)}, "UpperArm.R": {"rot": (18, 0, 0)},
         "LowerArm.L": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-14, 0, 0)},
         "Chest": {"rot": (2, 0, -4)}, "Hips": {"loc": (0, 0, 0)}}),
    (9, {"Thigh.L": {"rot": (6, 0, 0)}, "Thigh.R": {"rot": (-6, 0, 0)},
         "Shin.L": {"rot": (-22, 0, 0)}, "Shin.R": {"rot": (-12, 0, 0)},
         "UpperArm.L": {"rot": (-6, 0, 0)}, "UpperArm.R": {"rot": (6, 0, 0)},
         "LowerArm.L": {"rot": (-12, 0, 0)}, "LowerArm.R": {"rot": (-12, 0, 0)},
         "Chest": {"rot": (2, 0, 0)}, "Hips": {"loc": (0, 0, 0.022)}}),
    (17, {"Thigh.L": {"rot": (-26, 0, 0)}, "Thigh.R": {"rot": (26, 0, 0)},
          "Shin.L": {"rot": (-34, 0, 0)}, "Shin.R": {"rot": (-6, 0, 0)},
          "UpperArm.L": {"rot": (18, 0, 0)}, "UpperArm.R": {"rot": (-18, 0, 0)},
          "LowerArm.L": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-14, 0, 0)},
          "Chest": {"rot": (2, 0, 4)}, "Hips": {"loc": (0, 0, 0)}}),
    (25, {"Thigh.L": {"rot": (-6, 0, 0)}, "Thigh.R": {"rot": (6, 0, 0)},
          "Shin.L": {"rot": (-12, 0, 0)}, "Shin.R": {"rot": (-22, 0, 0)},
          "UpperArm.L": {"rot": (6, 0, 0)}, "UpperArm.R": {"rot": (-6, 0, 0)},
          "LowerArm.L": {"rot": (-12, 0, 0)}, "LowerArm.R": {"rot": (-12, 0, 0)},
          "Chest": {"rot": (2, 0, 0)}, "Hips": {"loc": (0, 0, 0.022)}}),
    (33, {"Thigh.L": {"rot": (26, 0, 0)}, "Thigh.R": {"rot": (-26, 0, 0)},
          "Shin.L": {"rot": (-6, 0, 0)}, "Shin.R": {"rot": (-34, 0, 0)},
          "UpperArm.L": {"rot": (-18, 0, 0)}, "UpperArm.R": {"rot": (18, 0, 0)},
          "LowerArm.L": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-14, 0, 0)},
          "Chest": {"rot": (2, 0, -4)}, "Hips": {"loc": (0, 0, 0)}}),
]


def pose_reset(rig):
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = 'XYZ'
        pose_bone.rotation_euler = (0.0, 0.0, 0.0)
        pose_bone.location = (0.0, 0.0, 0.0)
        pose_bone.scale = (1.0, 1.0, 1.0)


def build_action(rig, name, frames, end_frame):
    scene = bpy.context.scene
    scene.render.fps = 24
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = action
    pose_reset(rig)
    scene.frame_start = 1
    scene.frame_end = end_frame
    missing = set()
    for frame, poses in frames:
        scene.frame_set(frame)
        for bone_name, values in poses.items():
            pose_bone = rig.pose.bones.get(bone_name)
            if pose_bone is None:
                missing.add(bone_name)
                continue
            if "rot" in values:
                pose_bone.rotation_euler = tuple(math.radians(v) for v in values["rot"])
                pose_bone.keyframe_insert("rotation_euler", frame=frame)
            if "loc" in values:
                pose_bone.location = tuple(values["loc"])
                pose_bone.keyframe_insert("location", frame=frame)
    if missing:
        print("ACTION %s missing bones: %s" % (name, sorted(missing)))
    print("ACTION %s end=%d" % (name, end_frame))
    return action


def build_actions(rig):
    build_action(rig, "idle", IDLE, 72)
    build_action(rig, "walk", WALK, 33)
