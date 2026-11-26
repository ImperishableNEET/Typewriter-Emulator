extends RefCounted
## Fitted panels are the same mesh instances used by cutaway and camera collision.
const LABELS={"base_cover":"Bottom cover","inner_pan":"Inner mechanism pan"}
const LAYER=2048
var m
var desk
var colliders={}
var held=""
var start=Vector2.ZERO
var pull=0.
var dragged=false
var ray=PhysicsRayQueryParameters3D.new()

func setup(machine,owner):
	m=machine
	desk=owner
	for part in LABELS:
		var collider=StaticBody3D.new()
		collider.collision_mask=0
		collider.set_meta("panel",part)
		var shape=CollisionShape3D.new()
		shape.shape=m.parts[part].create_trimesh_shape()
		collider.add_child(shape)
		m.groups[part].get_child(0).add_child(collider)
		colliders[part]=collider
	update()

func update():
	for part in colliders:
		var fitted=not m.cut and bool(m.writer.data[part])
		m.groups[part].visible=fitted
		colliders[part].collision_layer=LAYER if fitted else 0
		m.groups[part].position=Vector3.DOWN*pull if part==held else Vector3.ZERO

func pick(pos:Vector2,_radius:float)->Dictionary:
	if m.cut or m.tilt>=0.:return {}
	var camera:Camera3D=m.camera
	ray.from=camera.project_ray_origin(pos)
	ray.to=ray.from+camera.project_ray_normal(pos)*40.
	ray.collision_mask=LAYER|m.action_grabs.FIXED_LAYER|m.action_grabs.COVER_LAYER|m.inspection.HARDWARE
	var hit=m.world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit.collider.has_meta("panel"):return {}
	var part:String=hit.collider.get_meta("panel")
	return {"label":LABELS[part],"distance":-1.,"tip":"Click or pull to remove the "+LABELS[part].to_lower()+". Refit it in Machine controls."}

func begin(label:String,pos:Vector2,_shifted:bool):
	held=LABELS.find_key(label)
	start=pos
	pull=0.
	dragged=false

func drag(pos:Vector2):
	if held=="":return
	var delta=pos-start
	if delta.length()>3.:dragged=true
	var origin=m.camera.unproject_position(Vector3.ZERO)
	var axis=m.camera.unproject_position(Vector3.DOWN)-origin
	if axis.length()<12.:axis=Vector2.DOWN*90.
	pull=clampf(delta.dot(axis.normalized())/maxf(axis.length(),70.),0.,.85)
	update()

func finish(cancelled:bool):
	if held=="":return
	if not cancelled and (not dragged or pull>.10):m.writer.data[held]=false
	held=""
	pull=0.
	update()
	desk.changed()

func reset_default(label:String):
	m.writer.data[LABELS.find_key(label)]=true
	update()
