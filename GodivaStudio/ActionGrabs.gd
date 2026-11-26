extends RefCounted
## Inverse operation of the same sampled actions used by the keyboard.
const GUIDE = "Type guide / shift segment"
var m
var paths = {}
var held = ""
var key = ""
var depth = 0.
var initial = 0.
var start = Vector2.ZERO
var contact = false
var returning = false
var grab_fraction = 1.
var fractions = {}
var caught_origin = {}
var shifted_input = false
# Independent physics layers let a cutaway hide its corresponding pick barriers.
const FIXED_LAYER = 256
const COVER_LAYER = 512
var barrier_query = PhysicsRayQueryParameters3D.new()

func setup(machine, _desk):
	m = machine
	for group in ["body","shell","hood","segment","rear_carriage_cover"]:
		if not m.parts.has(group):continue
		var collider=StaticBody3D.new()
		collider.collision_layer=FIXED_LAYER if group in ["body","segment"] else COVER_LAYER
		collider.collision_mask=0
		var shape=CollisionShape3D.new()
		shape.shape=m.parts[group].create_trimesh_shape()
		collider.add_child(shape)
		m.groups[group].get_child(0).add_child(collider)
	for k in m.key_grabs.type_tips:
		paths["Typebar "+k] = {"key":k, "bar":true}
		for group in m.key_action.tracks[k]:
			if not ("draw link" in group or "sublever" in group):continue
			var mesh = m.parts[group]
			var vertices:PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var frames = m.key_action.tracks[k][group]
			var furthest = vertices[0]
			var max_travel = 0.
			for v in vertices:
				var travel = (frames[12]*v).distance_squared_to(frames[0]*v)
				if travel>max_travel:
					max_travel=travel
					furthest=v
			var label = ("Draw link " if "draw link" in group else "Sublever ")+str(k)
			paths[label]={"key":k,"group":group,"handle":furthest,"center":mesh.get_aabb().get_center()}
	# Local Godot coordinates of the outer bearing faces on the shifted segment.
	paths[GUIDE]={"guide":true}

func position_at(label:String, q:float, fraction:float)->Vector3:
	if label==GUIDE:
		return Vector3(lerpf(-.077,.077,fraction),1.054+.066*q,-.687)
	var p:Dictionary=paths[label]
	if p.has("bar"):
		return m.key_grabs.bar_at(p.key,m.key_grabs.type_tips[p.key]*fraction,q)
	var frames:Array=m.key_action.tracks[p.key][p.group]
	var step=clampf(q,0.,1.)*12.
	var i=mini(11,floori(step))
	var low=frames[i].interpolate_with(frames[i+1],step-i)
	var high=frames[i+13].interpolate_with(frames[i+14],step-i)
	return low.interpolate_with(high,m.shift_offset/.066)*p.center.lerp(p.handle,fraction)

func current(label:String)->float:
	if label==GUIDE:return m.shift_offset/.066
	var k:String=paths[label].key
	if k==key and (held!="" or returning):return depth
	return clampf(m.key_action.previous.get(k,Vector2.ZERO).x/12.,0.,1.)

func pick(pos:Vector2,radius:float)->Dictionary:
	var best={}
	var limit=minf(6.,radius)
	var camera=m.camera
	for label in paths:
		var p:Dictionary=paths[label]
		if p.has("group") and not (m.cut or m.hood_grab.lift>.5 or (not m.writer.data.base_cover and not m.writer.data.inner_pan)):continue
		if p.has("bar") and m.writer.data.jammed and p.key in m.key_grabs.jam_keys:continue
		var q=current(label)
		var near=0. if not p.has("bar") else (.49 if m.cut else .90)
		var far=1.
		var a=camera.unproject_position(position_at(label,q,near))
		var b=camera.unproject_position(position_at(label,q,far))
		var axis=b-a
		var u=clampf((pos-a).dot(axis)/maxf(.00001,axis.length_squared()),0.,1.)
		if label==GUIDE:u=0. if u<.5 else 1.
		var dist=pos.distance_to(a+axis*u)
		if dist>=limit:continue
		var fraction=lerpf(near,far,u)
		var handle=position_at(label,q,fraction)
		# The displayed handle may be inside its own curved surface. Stop the
		# sight ray just short of it to allow for that thickness.
		var direction=camera.project_ray_normal(pos)
		barrier_query.from=camera.project_ray_origin(camera.unproject_position(handle))
		barrier_query.to=handle-direction*.025
		barrier_query.collision_mask=FIXED_LAYER if m.cut else FIXED_LAYER|COVER_LAYER|m.bottom_panels.LAYER
		if not m.world.get_world_3d().direct_space_state.intersect_ray(barrier_query).is_empty():continue
		limit=dist
		fractions[label]=lerpf(near,far,u)
		var tip="Drag "+str(label)+" through its stroke"
		if label==GUIDE:tip="Drag the steel guide with the shift segment; hold at the stop to type shifted"
		elif m.writer.data.jammed and p.key in m.key_grabs.jam_keys:tip="Pull this linkage back to free its typebar"
		best={"label":label,"distance":dist,"tip":tip}
	return best

func begin(label:String,pos:Vector2,shifted:bool):
	caught_origin=m.key_grabs.jam_snapshot() if m.writer.data.jammed else {}
	initial=current(label)
	if returning and key!="" and key!=paths[label].get("key",""):
		m.key_grabs.set_bar(key,0.)
	held=label
	key=paths[label].get("key","")
	depth=initial
	start=pos
	grab_fraction=fractions.get(label,1.)
	contact=initial>=m.key_grabs.STRIKE_DEPTH
	returning=false
	shifted_input=shifted
	m.key_grabs.depth=initial
	m.key_grabs.travel_velocity.reset(depth)

func drag(pos:Vector2):
	if held=="":return
	var target=m.camera.unproject_position(position_at(held,initial,grab_fraction))+pos-start
	var best_distance=INF
	var chosen=depth
	for i in 97:
		var q=i/96.
		var d=target.distance_squared_to(m.camera.unproject_position(position_at(held,q,grab_fraction)))
		if d<best_distance:
			best_distance=d
			chosen=q
	if held==GUIDE:
		depth=1. if m.writer.data.locked else chosen
		return
	var jam=key in m.key_grabs.jam_keys and m.writer.data.jammed
	if jam:
		depth=minf(initial,chosen)
		m.key_grabs.jam_positions[key]=depth
		if depth<=.23:
			m.key_grabs.free_jam()
			held=""
			key=""
		return
	depth=minf(chosen,m.key_grabs.available_key_travel(key))
	m.key_grabs.depth=depth
	m.key_grabs.sample_depth()
	if depth<=.04:contact=false
	if depth>=m.key_grabs.STRIKE_DEPTH and not contact:
		contact=true
		m.key_grabs.pointer_strength=m.key_grabs.measured_strength()
		m.operated.emit(key,shifted_input)
		m.key_grabs.pointer_strength=-1.

func reset_default(label:String):
	if label==GUIDE:
		m.key_grabs.reset_default("Shift lock")
	elif m.writer.data.jammed and paths[label].key in m.key_grabs.jam_keys:
		m.key_grabs.free_jam()

func finish(cancelled:bool):
	if cancelled and not caught_origin.is_empty():m.key_grabs.restore_jam(caught_origin)
	caught_origin={}
	returning=held!="" and held!=GUIDE and key!="" and not m.writer.data.jammed
	held=""

func update(dt:float):
	if returning:
		depth=move_toward(depth,0.,dt*16.)
		if depth==0.:
			m.key_grabs.set_bar(key,0.)
			key=""
			returning=false
