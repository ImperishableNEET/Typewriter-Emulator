extends RefCounted
## Sweep the orthographic near plane toward the requested eye from outside
## the model. The orbit pivot can be inside the mechanism being inspected.
const HARDWARE=1024
var query=PhysicsShapeQueryParameters3D.new()
var near_plane=BoxShape3D.new()
var offset=Vector3.ZERO
var focus=Vector3.ZERO

func setup(m):
	query.shape=near_plane
	query.margin=.008
	for label in m.parts:
		if not (label in ["carriage","platen","bail","roller_left","roller_right","reel_left","reel_right"] or label.begins_with("key:") or label.begins_with("bar:")):continue
		var shape=CollisionShape3D.new()
		shape.shape=m.parts[label].create_trimesh_shape()
		var body=StaticBody3D.new()
		body.collision_layer=HARDWARE
		body.collision_mask=0
		body.add_child(shape)
		m.groups[label].get_child(0).add_child(body)

func pan(m,delta:Vector2):
	var center=m.view.size*.5
	offset+=m.camera.project_position(center,1.)-m.camera.project_position(center+delta,1.)

func update(m):
	var cam:Camera3D=m.camera
	if not cam or m.size.x<1 or m.size.y<1:return
	var screen_size=Vector2(m.view.size)
	if screen_size.x<1 or screen_size.y<1:return
	focus=(Vector3(0,.94,-.39) if m.cut else Vector3(0,.91,-.02))+offset
	var basis=Basis(Vector3.UP,m.yaw)*Basis(Vector3.RIGHT,-m.tilt)
	var distance=m.zoom*1.44
	var eye=focus+basis.z*distance
	var show_floor:bool=m.writer.data.show_floor and (not m.cut or m.tilt>=.08)
	m.ground.visible=show_floor
	m.inspection_light.light_energy=.78*smoothstep(0.,.75,-sin(m.tilt)) if not show_floor else 0.
	cam.size=m.zoom*minf(1.,screen_size.y/screen_size.x)
	if m.writer.data.camera_collision:
		var height=cam.size
		var width=height*screen_size.x/screen_size.y
		var extent=Vector3(width,height,.025)
		if not near_plane.size.is_equal_approx(extent):near_plane.size=extent
		# Past the shell the camera still zooms optically without crossing it.
		var outside=maxf(6.+focus.length()+width+height,distance)
		var motion=basis.z*(distance-outside)
		if motion.length_squared()>.00001:
			query.transform=Transform3D(basis,focus+basis.z*outside)
			query.motion=motion
			query.collision_mask=HARDWARE|m.action_grabs.FIXED_LAYER|m.bottom_panels.LAYER
			if not m.cut:query.collision_mask|=m.action_grabs.COVER_LAYER
			var hit=m.world.get_world_3d().direct_space_state.cast_motion(query)
			if hit.size()==2:eye=query.transform.origin+motion*hit[0]
		if show_floor:eye.y=maxf(eye.y,.02)
	cam.transform=Transform3D(basis,eye)
