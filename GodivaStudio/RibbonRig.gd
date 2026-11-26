extends RefCounted
## Native selector, fork, feed carrier, pawl and wound ribbon poses.
const BAND_SHADER="""
shader_type spatial;
uniform vec4 ink : source_color;
uniform float lift;
uniform float back;
uniform vec3 left_tangent;
uniform vec3 right_tangent;
uniform vec3 left_eye = vec3(10.0);
uniform vec3 right_eye = vec3(10.0);
varying vec3 cloth_position;
void vertex() {
	float x = abs(VERTEX.x);
	float w = clamp((0.532 - x) / (0.532 - 0.173), 0.0, 1.0);
	VERTEX.y += lift * w;
	VERTEX.z -= back * w;
	if (x > 0.81) {
		VERTEX += VERTEX.x < 0.0 ? left_tangent : right_tangent;
	}
	cloth_position = VERTEX;
}
void fragment() {
	if (min(distance(cloth_position,left_eye),distance(cloth_position,right_eye)) < 0.0065) {
		discard;
	}
	ALBEDO = ink.rgb;
	ROUGHNESS = 0.93;
}
"""
const TOOTH_KNOTS=[0,8,18,19,20,38,60,78,90,92,108,128]
const MODES={"Stencil":0,"Black":1,"Split":2,"Red":3}
var machine
var rig:Dictionary
var lift:Dictionary
var feed:Dictionary
var guide:Dictionary
var tooth:Dictionary
var guide_travel=0.
var selector_mode=1.
var displayed_position=3000.
var position_sample=[]
var last_position=-1.
var moving_keys={}
var last_pose=Vector4(-1,-1,-1,-1)

func setup(host,manifest:Dictionary):
	machine=host
	rig=manifest
	lift=machine.load_actuator_tracks(rig.lift)
	feed=machine.load_actuator_tracks(rig.feed)
	guide=machine.load_actuator_tracks(rig.guide)
	tooth=machine.load_actuator_tracks(rig.tooth)
	for tracks in [lift,feed,guide,tooth]:
		for key in tracks:moving_keys[key]=true
	displayed_position=float(host.writer.data.ribbon_pos)
	selector_mode=float(MODES[host.writer.data.ribbon])
	guide_travel=1. if int(host.writer.data.direction)<0 else 0.

static func lower_knot(position:float,table:Array)->int:
	var low=0
	var high=table.size()-1
	while high-low>1:
		var mid=(low+high)>>1
		if table[mid][0]<=position:low=mid
		else:high=mid
	return low

static func advance(position:float,direction:int,table:Array)->float:
	var i=lower_knot(position,table)
	var a:Array=table[i]
	var b:Array=table[i+1]
	var f=clampf(inverse_lerp(float(a[0]),float(b[0]),position),0.,1.)
	var col=15 if direction<0 else 16
	var dest=clampf(position+lerpf(float(a[col]),float(b[col]),f),0.,6000.)
	if dest<0.000001:return 0.
	if dest>5999.999999:return 6000.
	return dest

func tween(poses:Array,value:float,offset:int=0)->Transform3D:
	var p=clampf(value,0.,1.)*4.
	var i=mini(3,floori(p))
	return poses[offset+i].interpolate_with(poses[offset+i+1],p-i)

func pawl(poses:Array,phase:float)->Transform3D:
	var where=fposmod(phase,1.)*128.
	for i in range(TOOTH_KNOTS.size()-1):
		if where<=TOOTH_KNOTS[i+1]:
			var f=inverse_lerp(float(TOOTH_KNOTS[i]),float(TOOTH_KNOTS[i+1]),where)
			return poses[i].interpolate_with(poses[i+1],f)
	return poses.back()

func tangent(side:String,radius:float)->Vector3:
	# Pack-to-guide tangent on the ribbon surface, in the native millimetre frame.
	var dx=-26.
	var dy=11.857 if side=="left" else 15.771
	var square=dx*dx+dy*dy
	var arc=sqrt(square-radius*radius)
	var sign_x=-1. if side=="left" else 1.
	var x=99.+(radius*radius*dx+radius*arc*dy)/square
	var y=50.+(radius*radius*dy-radius*arc*dx)/square
	return (sign_x*x*machine.vec(rig.root_x)+y*machine.vec(rig.root_y))*.01

func update(dt:float,state:Dictionary,stroke:float):
	if not machine:return
	var position=float(state.ribbon_pos)
	if absf(position-displayed_position)>8.:displayed_position=position
	else:displayed_position=move_toward(displayed_position,position,dt*70.)
	guide_travel=move_toward(guide_travel,1. if state.direction<0 else 0.,dt*8.)
	selector_mode=move_toward(selector_mode,float(MODES[state.ribbon]),dt*16.)
	var pose=Vector4(displayed_position,guide_travel,selector_mode,stroke)
	if pose.is_equal_approx(last_pose):return
	last_pose=pose
	if last_position!=displayed_position:
		var table:Array=rig.transport
		var i=lower_knot(displayed_position,table)
		var a:Array=table[i]
		var b:Array=table[i+1]
		var f=inverse_lerp(float(a[0]),float(b[0]),displayed_position)
		position_sample.resize(a.size())
		for j in a.size():position_sample[j]=lerpf(float(a[j]),float(b[j]),f)
		last_position=displayed_position
	var r=position_sample
	var stage=mini(2,floori(selector_mode))
	for k in moving_keys:
		var transform=Transform3D.IDENTITY
		if lift.has(k):
			var p=tween(lift[k],stroke,stage*5)
			transform=p.interpolate_with(tween(lift[k],stroke,(stage+1)*5),selector_mode-stage)
		if feed.has(k):transform=transform*tween(feed[k],stroke)
		if guide.has(k):transform=transform*tween(guide[k],guide_travel)
		if tooth.has(k):
			var left="Left" in k
			var angle=float(r[1] if left else r[8])
			transform=transform*pawl(tooth[k],3.*stroke+(-1. if left else 1.)*angle/(TAU/80.))
		machine.groups[k].transform=transform
	for k in rig.springs:
		machine.groups[k].get_child(0).set_blend_shape_value(0,guide_travel)
	for side in ["left","right"]:
		var side_index=0 if side=="left" else 1
		var radius=float(r[2] if side=="left" else r[9])
		var displacement=tangent(side,radius)-tangent(side,float(rig.initial_radius[side_index]))
		for band in machine.band_materials:
			band.set_shader_parameter(side+"_tangent",displacement)
		var reel=machine.groups.get("reel_"+side)
		if reel:reel.rotation.y=float(r[1] if side=="left" else r[8])
	for k in rig.packs:
		var left=rig.packs[k]=="left"
		var pivot:Vector3=machine.fittings["reel_left" if left else "reel_right"]
		var basis=Basis(Vector3.UP,float(r[1] if left else r[8]))
		machine.groups[k].transform=Transform3D(basis,pivot-basis*pivot)
		var radius=float(r[2] if left else r[9])
		machine.groups[k].get_child(0).set_blend_shape_value(0,(radius-float(rig.initial_radius[0 if left else 1]))/10.)
	for k in rig.eyes:
		var j=1 if rig.eyes[k]=="left" else 8
		var eye=machine.groups[k]
		eye.visible=r[j+5]>=-.1 and r[j+5]<=r[j+6]+.1
		var aperture=Vector3(10.,10.,10.)
		if eye.visible:
			var rest:Array=rig.eye_rest[k]
			var x=machine.vec(rig.root_x)
			var y=machine.vec(rig.root_y)
			var origin=machine.vec(rig.root_origin)
			var from=origin+x*float(rest[0])+y*float(rest[1])
			var to=origin+x*float(r[j+2])+y*float(r[j+3])
			var rotation=Basis(x.cross(y).normalized(),float(r[j+4])-float(rest[2]))
			eye.transform=Transform3D(rotation,to-rotation*from)
			aperture=eye.transform*eye.get_child(0).get_aabb().get_center()
		for band in machine.band_materials:band.set_shader_parameter(rig.eyes[k]+"_eye",aperture)
