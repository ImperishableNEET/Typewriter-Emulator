extends RefCounted

const KEYS = ["+", "−", "···", "TAB"]
const BLADE = "tab_part:Tab bank | D arrest blade"
const PITCH = .025
const PRESS_TIME = .060

var machine
var spec:Dictionary
var tracks:Dictionary = {}
var pressures:Dictionary = {}
var remaining:Dictionary = {}
var press_times:Dictionary = {}
var rider_state:Dictionary = {}
var blade_material:ShaderMaterial
var run:Array = []
var cursor := 0
var elapsed := 0.
var origin := 0.
var destination := 0.
var start_column := 0
var waiting := false
var blade_mm := 0.
var initialized := false

func setup(owner):
	machine=owner
	spec=owner.writer.meta.get("tab_rig",{})
	if spec.is_empty():return
	for key in KEYS:
		tracks[key]=owner.load_actuator_tracks(spec.tracks[key])
		pressures[key]=0.
		remaining[key]=0.
		press_times[key]=PRESS_TIME
	# The anchor ear and its rivets are separate margin-release meshes on the
	# loose dog. Preserve their own local drives while the tab key lifts the dog.
	var loose:Node3D
	for name in tracks["TAB"]:
		if name.begins_with("tab_part:Escapement | Loose dog"):
			loose=owner.groups[name]
			break
	if loose:
		for name in owner.groups:
			if name.begins_with("margin_part:Margin release | A "):
				owner.groups[name].reparent(loose,false)
	var blade:MeshInstance3D=owner.groups[BLADE].get_child(0)
	var mat:StandardMaterial3D=blade.mesh.surface_get_material(0)
	var shader=Shader.new()
	shader.code="""shader_type spatial;
	uniform vec4 color : source_color;
	uniform float metal;
	uniform float rough;
	uniform vec2 blade_y;
	uniform float offset_mm;
	void vertex(){
		float h=clamp((VERTEX.y-blade_y.x)/(blade_y.y-blade_y.x),0.0,1.0);
		VERTEX.x+=0.01*offset_mm*h*h*(3.0-h)/2.0;
	}
	void fragment(){ALBEDO=color.rgb;METALLIC=metal;ROUGHNESS=rough;}"""
	blade_material=ShaderMaterial.new()
	blade_material.shader=shader
	blade_material.set_shader_parameter("color",mat.albedo_color)
	blade_material.set_shader_parameter("metal",mat.metallic)
	blade_material.set_shader_parameter("rough",mat.roughness)
	blade_material.set_shader_parameter("blade_y",Vector2(spec.blade_bounds[0],spec.blade_bounds[1]))
	blade.set_surface_override_material(0,blade_material)

func press(key:String,stroke_duration:=.105)->bool:
	if spec.is_empty() or key not in KEYS:return false
	press_times[key]=clampf(PRESS_TIME*stroke_duration/.105,.025,.13)
	remaining[key]=press_times[key]
	if key=="TAB":
		start_column=int(machine.writer.data.col)
		waiting=true
		run=[]
	return true

func carriage_position(dt:float,normal:float)->float:
	if spec.is_empty():return normal
	if waiting:
		waiting=false
		var finish=int(machine.writer.data.col)
		var span=finish-start_column
		if span>0 and span<spec.dynamics[0].size():
			run=spec.dynamics[int(finish in machine.writer.data.tabs)][span]
			cursor=0
			elapsed=-float(press_times["TAB"])
			destination=machine.target_travel
			origin=destination+span*PITCH
			remaining["TAB"]=press_times["TAB"]+float(run.back()[0])
	if run.is_empty():return normal
	if not is_equal_approx(destination,machine.target_travel):
		run=[]
		remaining["TAB"]=0.
		blade_mm=0.
		return normal
	elapsed+=dt
	if elapsed<0.:return origin
	if elapsed>=float(run.back()[0]):
		run=[]
		blade_mm=0.
		return destination
	while cursor+1<run.size()-1 and float(run[cursor+1][0])<=elapsed:
		cursor+=1
	var a:Array=run[cursor]
	var b:Array=run[cursor+1]
	var weight=clampf(inverse_lerp(a[0],b[0],elapsed),0.,1.)
	blade_mm=lerpf(a[2],b[2],weight)
	return origin-PITCH*lerpf(a[1],b[1],weight)

func update(dt:float):
	if spec.is_empty():return
	var transforms={}
	for key in KEYS:
		var prev:float=pressures[key]
		pressures[key]=move_toward(prev,1. if remaining[key]>0. else 0.,dt/press_times[key])
		var hand_depth=machine.key_grabs.tab_depth(key)
		if hand_depth>=0. and (key!="TAB" or run.is_empty()):pressures[key]=hand_depth
		remaining[key]=maxf(0.,remaining[key]-dt)
		var amount:float=pressures[key]*4.
		var step=mini(3,floori(amount))
		for name in tracks[key]:
			var samples:Array=tracks[key][name]
			var pose:Transform3D=samples[step].interpolate_with(samples[step+1],amount-step)
			transforms[name]=transforms.get(name,Transform3D.IDENTITY)*pose
	for name in transforms:
		machine.groups[name].transform=transforms[name]
	# The printable sheet origin can fall between escapement pitches. Align the
	# whole working bank to the sheet's nearest physical stop, including the rail.
	var writer=machine.writer
	var center=(writer.dimensions().x*.5-writer.MARGIN)/writer.PITCH-.5
	var datum=roundi(center)
	var bank_x=machine.travel+(datum-center)*PITCH
	for name in spec.traveling:
		var pose:Transform3D=transforms.get(name,Transform3D.IDENTITY)
		pose.origin.x+=bank_x
		machine.groups[name].transform=pose
	var armed_offset:Vector3=machine.vec(spec.rider_offset)
	for name in spec.riders:
		var col=datum+int(spec.riders[name])
		var goal=1. if col in writer.data.tabs else 0.
		var state=goal if not initialized else move_toward(float(rider_state.get(name,goal)),goal,dt/PRESS_TIME)
		rider_state[name]=state
		machine.groups[name].position=Vector3(bank_x,0,0)+armed_offset*state
	blade_material.set_shader_parameter("offset_mm",blade_mm)
	initialized=true
