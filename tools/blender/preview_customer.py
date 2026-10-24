"""Render a quick portrait of a customer GLB so the mesh can be eyeballed.

Usage: blender -b --factory-startup -P preview_customer.py -- <glb> <out.png>
"""
import os
import sys

import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
glb_path = argv[0]
out_png = argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb_path)

target = bpy.data.objects.new("Target", None)
bpy.context.collection.objects.link(target)
target.location = (0.0, 0.0, 0.95)

cam_data = bpy.data.cameras.new("PreviewCam")
cam = bpy.data.objects.new("PreviewCam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = (1.9, -2.6, 1.75)
cam.data.lens = 60
track = cam.constraints.new('TRACK_TO')
track.target = target
track.track_axis = 'TRACK_NEGATIVE_Z'
track.up_axis = 'UP_Y'
bpy.context.scene.camera = cam

sun_data = bpy.data.lights.new("Sun", type='SUN')
sun_data.energy = 4.0
sun = bpy.data.objects.new("Sun", sun_data)
bpy.context.collection.objects.link(sun)
sun.rotation_euler = (0.9, 0.1, 0.7)

fill_data = bpy.data.lights.new("Fill", type='AREA')
fill_data.energy = 120.0
fill_data.size = 3.0
fill = bpy.data.objects.new("Fill", fill_data)
bpy.context.collection.objects.link(fill)
fill.location = (-2.2, -1.6, 2.2)

scene = bpy.context.scene
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 420
scene.render.resolution_y = 560
scene.render.film_transparent = False
world = bpy.data.worlds.new("W")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.16, 0.17, 0.20, 1.0)
scene.world = world
scene.render.filepath = out_png
bpy.ops.render.render(write_still=True)

# Close-up of the right hand so the digit layout can be counted.
cam.location = (0.85, -0.75, 0.95)
target.location = (0.29, 0.0, 0.79)
cam.data.lens = 85
scene.render.resolution_x = 420
scene.render.resolution_y = 420
scene.render.filepath = out_png.replace(".png", "_hand.png")
bpy.ops.render.render(write_still=True)
print("PREVIEW %s" % out_png)
