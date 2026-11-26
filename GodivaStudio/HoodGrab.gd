extends RefCounted
## Direct manipulation of the detachable hood at its front edge.
var machine
var desk
var root:Node3D
var origin=Vector2.ZERO
var initial=0.
var lift=0.
var goal=0.
var dragged=false
const TRAVEL=Vector3(0,1.50,-.38)

func setup(host,controller):
	machine=host
	desk=controller
	root=Node3D.new()
	machine.root.add_child(root)
	for group in machine.writer.meta.hood_groups:
		if machine.groups.has(group):machine.groups[group].reparent(root,true)

func pick(pos:Vector2,radius:float)->Dictionary:
	if machine.cut:return {}
	var anchor=machine.vec(machine.writer.meta.hood_grip)+root.position
	var a=machine.camera.unproject_position(anchor-Vector3.RIGHT*.56)
	var b=machine.camera.unproject_position(anchor+Vector3.RIGHT*.56)
	var distance=Geometry2D.get_closest_point_to_segment(pos,a,b).distance_to(pos)+3.
	if distance>radius*.83:return {}
	return {"label":"Ribbon cover","distance":distance,"tip":"Click to lift or seat the ribbon cover, or drag its front edge."}

func begin(_label:String,pos:Vector2,_shifted:bool):
	origin=pos
	initial=lift
	goal=lift
	dragged=false

func drag(pos:Vector2):
	var delta=pos-origin
	if delta.length()<3. and not dragged:return
	dragged=true
	var axis=machine.camera.unproject_position(TRAVEL)-machine.camera.unproject_position(Vector3.ZERO)
	goal=clampf(initial+delta.dot(axis)/maxf(1.,axis.length_squared()),0.,1.)
	lift=goal

func finish(cancelled:bool):
	if cancelled:goal=initial
	elif dragged:goal=roundf(lift)
	else:goal=1. if initial<.5 else 0.

func update(dt:float):
	lift=move_toward(lift,goal,dt*4.5)
	root.position=TRAVEL*lift

func reset_default(_label:String):
	goal=0.
