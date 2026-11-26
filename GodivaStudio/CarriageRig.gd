extends RefCounted
## Native, carriage-relative motion of the end buttons and flying-margin setters.

const LABELS=["Carriage release left","Carriage release right","Flying margin left","Flying margin right"]
const CHANNELS=["left","right","setter_left","setter_right"]
const PITCH=.025
var machine
var spec:Dictionary
var tracks={}
var held=[false,false,false,false]
var pulse=[0.,0.,0.,0.]
var pressure=[0.,0.,0.,0.]
var tape_materials:Array[ShaderMaterial]=[]

func setup(owner):
	machine=owner
	spec=owner.writer.meta.get("carriage_rig",{})
	if spec.is_empty():return
	for channel in spec.tracks:
		tracks[channel]=machine.load_actuator_tracks(spec.tracks[channel])
	var shader=Shader.new()
	shader.code="""shader_type spatial;
	uniform vec4 pigment : source_color;
	uniform float metal;
	uniform float rough;
	uniform mat4 hinge;
	void vertex() {
		// The front arc and the first pulley are on the hinged bail. The two
		// rear pulley arcs stay on the carriage. Their joining span follows both.
		if (VERTEX.z > -1.0) {
			VERTEX=(hinge*vec4(VERTEX,1.)).xyz;
			NORMAL=(mat3(hinge)*NORMAL);
		}
	}
	void fragment(){ALBEDO=pigment.rgb;METALLIC=metal;ROUGHNESS=rough;}"""
	for name in spec.optical:
		if "continuous indicator tape" not in name:continue
		var inst:MeshInstance3D=machine.groups[name].get_child(0)
		var mat:StandardMaterial3D=inst.mesh.surface_get_material(0)
		var tape=ShaderMaterial.new()
		tape.shader=shader
		tape.set_shader_parameter("pigment",mat.albedo_color)
		tape.set_shader_parameter("metal",mat.metallic)
		tape.set_shader_parameter("rough",mat.roughness)
		tape.set_shader_parameter("hinge",Transform3D.IDENTITY)
		inst.set_surface_override_material(0,tape)
		tape_materials.append(tape)

func set_control(label:String,down:bool):
	var i=LABELS.find(label)
	if i<0:return
	held[i]=down
	if down:pulse[i]=.10

func tap(label:String):
	var i=LABELS.find(label)
	if i>=0:pulse[i]=.12

func point(label:String)->Vector3:
	if not spec.has("targets") or not spec.targets.has(label):return Vector3.ZERO
	var target:Array=spec.targets[label]
	return machine.groups[target[0]].transform * machine.vec(target[1])

func sample(track:Array,amount:float)->Transform3D:
	var phase=clampf(amount,0.,1.)*4.
	var i=mini(3,floori(phase))
	return track[i].interpolate_with(track[i+1],phase-i)

func update(dt:float):
	if spec.is_empty():return
	var poses={}
	for i in CHANNELS.size():
		var down=held[i] or pulse[i]>0.
		pressure[i]=move_toward(pressure[i],1. if down else 0.,dt*14.)
		pulse[i]=maxf(0.,pulse[i]-dt)
		for name in tracks[CHANNELS[i]]:
			poses[name]=sample(tracks[CHANNELS[i]][name],pressure[i])
	var shared=maxf(pressure[0],pressure[1])
	for name in tracks.shared:
		var pose=sample(tracks.shared[name],shared)
		if name.begins_with("tab_part:"):
			# Tab and hand release act upon the same dog. TabRig has already
			# positioned it for this frame; keep the larger withdrawal.
			if pose.origin.length_squared()>machine.groups[name].transform.origin.length_squared():
				machine.groups[name].transform=pose
		else:poses[name]=pose
	var relative=machine.writer.meta.margin_reference
	var center=(machine.writer.dimensions().x*.5-machine.writer.MARGIN)/machine.writer.PITCH-.5
	var left=float(machine.writer.data.left)-center-float(relative[0])
	var right=float(machine.writer.data.right)+1.-center-float(relative[1])
	var columns={"column":-machine.travel/PITCH,"left_margin":left,"right_margin":right}
	for name in spec.rollers:
		var wheel:Array=spec.rollers[name]
		var angle:float=columns[wheel[0]]*wheel[3]
		var pivot:Vector3=machine.vec(wheel[1])
		var basis=Basis(machine.vec(wheel[2]).normalized(),angle)
		poses[name]=Transform3D(basis,pivot-basis*pivot)
	for name in spec.optical:
		var cfg=spec.optical[name]
		if cfg is String:
			poses[name]=Transform3D(Basis.IDENTITY,Vector3.RIGHT*(left if cfg=="left" else right)*PITCH)
		else:
			var mesh:MeshInstance3D=machine.groups[name].get_child(0)
			if cfg[0]=="spring":
				poses[name]=Transform3D(Basis.IDENTITY,Vector3.RIGHT*left*PITCH)
				mesh.set_blend_shape_value(0,(right-left)/cfg[1])
			else:mesh.set_blend_shape_value(0,(left if cfg[0]=="left" else right)/cfg[1])

	var carry=Transform3D(Basis.IDENTITY,Vector3.RIGHT*machine.travel)
	var hinge=Transform3D.IDENTITY
	if machine.groups.has("bail"):
		hinge=carry.affine_inverse()*machine.groups.bail.transform*Transform3D(Basis.IDENTITY,-machine.fittings.bail)
	for tape in tape_materials:tape.set_shader_parameter("hinge",hinge)
	for name in spec.mounts:
		if name.begins_with("tab_part:"):continue
		var pose:Transform3D=poses.get(name,Transform3D.IDENTITY)
		var mount:String=spec.mounts[name]
		if mount=="carriage":pose=carry*pose
		elif mount=="bail":pose=carry*hinge*pose
		elif mount.begins_with("margin_stop:"):pose=machine.groups[mount].transform*pose
		machine.groups[name].transform=pose
