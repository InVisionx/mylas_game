"""Builds, rigs and animates the low-poly customer used by Night Shift.

    blender.exe --background --factory-startup --python tools/blender/build_customer_rig.py

Writes models/customers/customer_a.glb containing one skinned mesh
("CustomerBody"), an armature ("CustomerRig", 19 deform bones) and two actions
("idle", "walk"). The character faces +Y in Blender, which exports as -Z in Godot.
"""

import bpy
import math
import os
import json
import struct
from mathutils import Vector

OUT_DIR = r"C:/Users/mattm/Desktop/mylas game/models/customers"
OUT_GLB = os.path.join(OUT_DIR, "customer_a.glb")


def clean():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for arm in list(bpy.data.armatures):
        bpy.data.armatures.remove(arm)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def mat(name, color, rough=0.8, metal=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    return m


def build_body():
    skin_mat = mat("Skin", (0.78, 0.60, 0.47))
    shirt_mat = mat("Shirt", (0.22, 0.30, 0.42))
    pants_mat = mat("Pants", (0.16, 0.17, 0.20))
    hair_mat = mat("Hair", (0.10, 0.08, 0.07))
    shoe_mat = mat("Shoe", (0.07, 0.07, 0.08))
    eye_mat = mat("Eye", (0.94, 0.94, 0.92))

    parts = []

    def box(name, size, loc, material):
        bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
        o = bpy.context.object
        o.name = name
        o.scale = (size[0], size[1], size[2])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        o.data.materials.append(material)
        parts.append(o)
        return o

    box("Pelvis", (0.32, 0.20, 0.18), (0, 0, 0.99), pants_mat)
    box("Torso", (0.40, 0.24, 0.42), (0, 0, 1.28), shirt_mat)
    box("NeckGeom", (0.12, 0.12, 0.10), (0, 0, 1.53), skin_mat)
    box("HeadGeom", (0.24, 0.23, 0.25), (0, 0.005, 1.68), skin_mat)
    box("HairGeom", (0.25, 0.24, 0.07), (0, -0.005, 1.80), hair_mat)
    box("Brow", (0.24, 0.05, 0.04), (0, 0.105, 1.745), hair_mat)
    box("Nose", (0.05, 0.05, 0.05), (0, 0.125, 1.66), skin_mat)
    box("EyeL", (0.05, 0.02, 0.035), (-0.06, 0.118, 1.70), eye_mat)
    box("EyeR", (0.05, 0.02, 0.035), (0.06, 0.118, 1.70), eye_mat)

    for s in (-1, 1):
        tag = "L" if s > 0 else "R"
        box("Shoulder." + tag, (0.10, 0.12, 0.12), (s * 0.24, 0, 1.45), shirt_mat)
        box("UpperArm." + tag, (0.11, 0.11, 0.30), (s * 0.27, 0, 1.30), shirt_mat)
        box("LowerArm." + tag, (0.09, 0.09, 0.26), (s * 0.27, 0, 1.02), skin_mat)
        box("Hand." + tag, (0.08, 0.05, 0.11), (s * 0.27, 0, 0.84), skin_mat)
        box("Thigh." + tag, (0.14, 0.15, 0.44), (s * 0.10, 0, 0.76), pants_mat)
        box("Shin." + tag, (0.12, 0.13, 0.42), (s * 0.10, 0, 0.32), pants_mat)
        box("Foot." + tag, (0.14, 0.24, 0.09), (s * 0.10, 0.05, 0.045), shoe_mat)

    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "CustomerBody"
    body.data.name = "CustomerBodyMesh"
    return body


def build_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "CustomerRig"
    rig.data.name = "CustomerArmature"
    eb = rig.data.edit_bones
    for b in list(eb):
        eb.remove(b)

    def bone(name, head, tail, parent=None, connect=False):
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        if parent:
            b.parent = eb[parent]
            b.use_connect = connect
        return b

    bone("Hips", (0, 0, 0.95), (0, 0, 1.08))
    bone("Spine", (0, 0, 1.08), (0, 0, 1.30), "Hips", True)
    bone("Chest", (0, 0, 1.30), (0, 0, 1.50), "Spine", True)
    bone("Neck", (0, 0, 1.50), (0, 0, 1.58), "Chest", True)
    bone("Head", (0, 0, 1.58), (0, 0, 1.82), "Neck", True)
    for s in (1, -1):
        tag = "L" if s > 0 else "R"
        bone("Shoulder." + tag, (0.05 * s, 0, 1.46), (0.24 * s, 0, 1.46), "Chest")
        bone("UpperArm." + tag, (0.24 * s, 0, 1.46), (0.27 * s, 0, 1.16), "Shoulder." + tag, True)
        bone("LowerArm." + tag, (0.27 * s, 0, 1.16), (0.27 * s, 0, 0.90), "UpperArm." + tag, True)
        bone("Hand." + tag, (0.27 * s, 0, 0.90), (0.27 * s, 0, 0.78), "LowerArm." + tag, True)
        bone("Thigh." + tag, (0.10 * s, 0, 0.96), (0.10 * s, 0, 0.54), "Hips")
        bone("Shin." + tag, (0.10 * s, 0, 0.54), (0.10 * s, 0, 0.10), "Thigh." + tag, True)
        bone("Foot." + tag, (0.10 * s, 0, 0.10), (0.10 * s, 0.18, 0.04), "Shin." + tag, True)

    bpy.ops.object.mode_set(mode='OBJECT')
    return rig


def dist_to_segment(p, a, b):
    ab = b - a
    denom = ab.length_squared
    if denom < 1e-9:
        return (p - a).length
    t = max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * t)).length


def skin(body, rig):
    """Nearest-bone binding, blended with the second nearest when close.
    Rigid enough for blocky limbs, soft enough at elbows and knees."""
    segments = [(b.name, b.head_local.copy(), b.tail_local.copy()) for b in rig.data.bones]
    groups = {}
    for name, _, _ in segments:
        groups[name] = body.vertex_groups.new(name=name)

    for vert in body.data.vertices:
        p = vert.co
        ranked = sorted((dist_to_segment(p, a, b), name) for name, a, b in segments)
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

    modifier = body.modifiers.new("Armature", 'ARMATURE')
    modifier.object = rig
    body.parent = rig
    weighted = sum(1 for v in body.data.vertices if len(v.groups) > 0)
    print("SKIN bones=%d groups=%d weighted=%d/%d" % (
        len(segments), len(body.vertex_groups), weighted, len(body.data.vertices)))


def pose_reset(rig):
    for pb in rig.pose.bones:
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)


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
    for frame, poses in frames:
        scene.frame_set(frame)
        for bone_name, values in poses.items():
            pb = rig.pose.bones[bone_name]
            if "rot" in values:
                pb.rotation_euler = tuple(math.radians(v) for v in values["rot"])
                pb.keyframe_insert("rotation_euler", frame=frame)
            if "loc" in values:
                pb.location = tuple(values["loc"])
                pb.keyframe_insert("location", frame=frame)
    curves = 0
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves += len(bag.fcurves)
    if curves == 0:
        curves = len(getattr(action, "fcurves", []))
    print("ACTION %s end=%d curves=%d" % (name, end_frame, curves))
    return action


def build_actions(rig):
    idle = [
        (1,  {"Chest": {"rot": (0, 0, 0)}, "Head": {"rot": (0, 0, 0)},
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
    walk = [
        (1,  {"Thigh.L": {"rot": (26, 0, 0)}, "Thigh.R": {"rot": (-26, 0, 0)},
              "Shin.L": {"rot": (-6, 0, 0)}, "Shin.R": {"rot": (-34, 0, 0)},
              "UpperArm.L": {"rot": (-18, 0, 0)}, "UpperArm.R": {"rot": (18, 0, 0)},
              "LowerArm.L": {"rot": (-14, 0, 0)}, "LowerArm.R": {"rot": (-14, 0, 0)},
              "Chest": {"rot": (2, 0, -4)}, "Hips": {"loc": (0, 0, 0)}}),
        (9,  {"Thigh.L": {"rot": (6, 0, 0)}, "Thigh.R": {"rot": (-6, 0, 0)},
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
    build_action(rig, "idle", idle, 72)
    build_action(rig, "walk", walk, 33)


def export_glb(rig, body):
    os.makedirs(OUT_DIR, exist_ok=True)
    if rig.animation_data:
        rig.animation_data.action = None
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = rig

    kwargs = dict(
        filepath=OUT_GLB,
        export_format='GLB',
        use_selection=True,
        export_apply=False,
        export_skins=True,
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_yup=True,
    )
    try:
        bpy.ops.export_scene.gltf(**kwargs)
    except TypeError as exc:
        print("EXPORT retry without optional params:", exc)
        bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', use_selection=True)
    print("EXPORTED %s %d bytes" % (OUT_GLB, os.path.getsize(OUT_GLB)))


def glb_summary(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if len(data) < 20 or data[0:4] != b'glTF':
        print("GLB invalid header")
        return
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_len].decode("utf-8"))
    print("GLB nodes=%d meshes=%d skins=%d materials=%d" % (
        len(doc.get("nodes", [])), len(doc.get("meshes", [])),
        len(doc.get("skins", [])), len(doc.get("materials", []))))
    for skin_def in doc.get("skins", []):
        print("GLB skin joints=%d" % len(skin_def.get("joints", [])))
    animations = doc.get("animations", [])
    if not animations:
        print("GLB animations=NONE")
    for anim in animations:
        print("GLB animation '%s' channels=%d" % (anim.get("name", "?"), len(anim.get("channels", []))))
    primitives = sum(len(m.get("primitives", [])) for m in doc.get("meshes", []))
    print("GLB primitives=%d" % primitives)


def main():
    clean()
    body = build_body()
    print("MESH verts=%d polys=%d materials=%d" % (
        len(body.data.vertices), len(body.data.polygons), len(body.data.materials)))
    rig = build_armature()
    print("RIG bones=%d" % len(rig.data.bones))
    skin(body, rig)
    build_actions(rig)
    export_glb(rig, body)
    glb_summary(OUT_GLB)


main()

