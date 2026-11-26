extends SubViewportContainer
signal operated(key:String,shifted:bool)
signal carriage_changed
var release_sources:Dictionary={}
var key_grabs=preload("res://KeyGrabs.gd").new()
var bail_grabs=preload("res://BailGrabs.gd").new()
var page_stack=preload("res://FinishedPageStack.gd").new()
var sheet_pull:=0.
var sheet_pull_side:=0.
var last_pull_side:=0.
var last_sheet_pull:=0.
var paper_in_machine:=true
var paper_grabs=preload("res://PaperGrabs.gd").new()
var hood_grab=preload("res://HoodGrab.gd").new()
var key_action=preload("res://KeyActionRig.gd").new()
var action_grabs=preload("res://ActionGrabs.gd").new()
var grab_providers=[]
var grab_owner
var double_click_reset=preload("res://DoubleClickReset.gd").new()
var carriage_dragging=false
var carriage_drag_origin=0.
var carriage_original_bypass=false
var suppress_cancel_orbit=false
var drag_position=Vector2.ZERO
var mouse_setter=""
var touch_lever=preload("res://TouchLeverRig.gd").new()
var carriage_rig=preload("res://CarriageRig.gd").new()
const CLEAR_PLASTIC_SHADER="""
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec4 tint : source_color;
uniform float transmission;
uniform float reflectance;
uniform float surface_roughness;
void fragment() {
	float incidence = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = reflectance + (1.0-reflectance)*pow(1.0-incidence, 5.0);
	ALBEDO = tint.rgb;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.5;
	ALPHA = 1.0-transmission*(1.0-fresnel);
}
"""
var view:SubViewport
var inspection_light:DirectionalLight3D
var ground:MeshInstance3D
var world:Node3D
var camera:Camera3D
var root:Node3D
var groups={}
var parts={}
var keys={}
var travel=0.
var target_travel=0.
var bottom_panels=preload("res://BottomPanels.gd").new()
var inspection=preload("res://InspectionCamera.gd").new()
var yaw=.12
var tilt=.64
const OPERATOR_ZOOM=7.95
const DESK_FOCUS=Vector3(.86,.19,-.04)
var zoom=OPERATOR_ZOOM
var cut=false
var motions:Array=[]
var writer
var tab_rig=preload("res://TabRig.gd").new()
var ribbon_rig=preload("res://RibbonRig.gd").new()
var sheet:MeshInstance3D
var stock_material:ShaderMaterial
const PAPER_SHADER="""
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D sheet_image : source_color, filter_linear;
uniform vec4 stock : source_color;
void fragment() {
	vec3 face = texture(sheet_image, UV).rgb;
	vec3 fiber = FRONT_FACING ? face : mix(stock.rgb, face, 0.08);
	ALBEDO = fiber * 0.65;
	EMISSION = fiber * 0.32;
	ROUGHNESS = 1.0;
}
"""
var last_half=-1
var last_stock=""
var last_texture:Texture2D
var band_materials=[]
var shift_offset=0.
var return_phase=0.
var return_duration=.37
var bail_angle=0.
var fittings={"bail":Vector3(0,1.338,-1.311),"roller_left":Vector3(-.33,1.341,-.855),"roller_right":Vector3(.33,1.341,-.855),"return_lever":Vector3(-1.49,1.282,-.83),"platen":Vector3(0,1.13,-.91),"reel_left":Vector3(-.99,1.02,-.5),"reel_right":Vector3(.99,1.02,-.5)}
var margin_key_held=false
var margin_key_pulse=0.
var margin_press=0.
var margin_bypass=0.
var margin_tracks={}
var margin_flex={}
var margin_samples=[]
var shift_tracks={}
var shared_shift_tracks={}
var shared_shift_depth=0.
var shift_excursion=0.
var shift_bottom_contact=false
var shift_return_speed=0.
var shift_sound_source="Left shift"
var shift_inputs=Vector2.ZERO
var shift_pulse=Vector2.ZERO
var shift_pose=Vector3.ZERO
var last_shift_pose=Vector3(-1,-1,-1)
var clicked_shift=0
var margin_pose=Vector3(-1,-1,-1)
var key_latched=false
var active=true
func vec(a)->Vector3:return Vector3(a[0],a[1],a[2])
func setup(w):
	writer=w;stretch=true;mouse_filter=Control.MOUSE_FILTER_STOP
	view=SubViewport.new();view.handle_input_locally=false;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view.msaa_3d=Viewport.MSAA_2X
	add_child(view)
	world=Node3D.new();view.add_child(world)
	var env=Environment.new();env.background_mode=Environment.BG_COLOR;env.background_color=Color("#34483f")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("#e4e7d7");env.ambient_light_energy=.42
	var we=WorldEnvironment.new();we.environment=env;world.add_child(we)
	root=Node3D.new();world.add_child(root)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.01;camera.far=40.;world.add_child(camera);camera.current=true
	for spec in [[Vector3(-3,6,4),.74,Color("#ffefd3")],[Vector3(3,2,-3),.38,Color("#bededb")]]:
		var light=DirectionalLight3D.new();world.add_child(light);light.position=spec[0];light.look_at(Vector3.ZERO);light.light_energy=spec[1];light.light_color=spec[2];light.shadow_enabled=spec[1]>.6
	inspection_light=DirectionalLight3D.new()
	world.add_child(inspection_light)
	inspection_light.position=Vector3(-2,-4,2)
	inspection_light.look_at(Vector3.ZERO,Vector3.UP)
	inspection_light.light_color=Color("#ede6d6")
	ground=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(35,35);ground.mesh=plane
	var floor_mat=StandardMaterial3D.new();floor_mat.albedo_color=Color("#40554b");floor_mat.roughness=.96;ground.material_override=floor_mat;world.add_child(ground);ground.position.y=-.005
	var meta=w.meta
	var mats={}
	for n in meta.materials:
		var cfg=meta.materials[n];var mat=StandardMaterial3D.new();var c=cfg[0]
		mat.albedo_color=Color(c[0],c[1],c[2]).linear_to_srgb().darkened(.19);mat.metallic=clampf(cfg[1]*.55,0,.65);mat.roughness=clampf(cfg[2],.24,.95);mats[n]=mat
		if cfg.size()>4 and cfg[3]>0.:
			var shader=Shader.new()
			shader.code=CLEAR_PLASTIC_SHADER
			var clear=ShaderMaterial.new()
			clear.shader=shader
			clear.set_shader_parameter("tint",Color(c[0],c[1],c[2]).linear_to_srgb())
			clear.set_shader_parameter("transmission",cfg[3])
			clear.set_shader_parameter("reflectance",pow((cfg[4]-1.)/(cfg[4]+1.),2.))
			clear.set_shader_parameter("surface_roughness",cfg[2])
			mats[n]=clear
	var file=FileAccess.open(w.machine_profile.geometry_path,FileAccess.READ)
	for spec in meta.parts:
		var group:String=spec[0]
		if not parts.has(group):parts[group]=ArrayMesh.new()
		file.seek(int(spec[2]));var nv=int(spec[3]);var ni=int(spec[4])
		var array=[];array.resize(Mesh.ARRAY_MAX)
		array[Mesh.ARRAY_VERTEX]=read_vectors(file,nv)
		array[Mesh.ARRAY_NORMAL]=read_vectors(file,nv)
		array[Mesh.ARRAY_INDEX]=file.get_buffer(ni*4).to_int32_array()
		var mesh:ArrayMesh=parts[group]
		if spec.size()>5 and spec[5]:
			if mesh.get_blend_shape_count()==0:mesh.add_blend_shape("Slide withdrawal")
			mesh.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_NORMALIZED
			var morph=[];morph.resize(Mesh.ARRAY_MAX)
			morph[Mesh.ARRAY_VERTEX]=read_vectors(file,nv);morph[Mesh.ARRAY_NORMAL]=read_vectors(file,nv)
			var morphs:Array[Array]=[morph]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,array,morphs)
		else:mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,array)
		if group=="ribbon":
			var shader=Shader.new();shader.code=ribbon_rig.BAND_SHADER
			var sm=ShaderMaterial.new();sm.shader=shader;sm.set_shader_parameter("ink",mats[spec[1]].albedo_color);band_materials.append(sm);mesh.surface_set_material(mesh.get_surface_count()-1,sm)
		else:mesh.surface_set_material(mesh.get_surface_count()-1,mats[spec[1]])
	file.close()
	for group in parts:
		var inst=MeshInstance3D.new();inst.mesh=parts[group]
		var pivot=Node3D.new();root.add_child(pivot);pivot.add_child(inst);groups[group]=pivot
		if group.begins_with("bar:"):
			var ref=vec(meta.bars[group.substr(4)].pivot);pivot.position=ref;inst.position=-ref
		if fittings.has(group):
			pivot.position=fittings[group];inst.position=-pivot.position
	margin_samples=meta.get("margin_samples",[-2.,0.])
	margin_flex=meta.get("margin_flex",{})
	margin_tracks=load_actuator_tracks(meta.get("margin_motion",{}))
	shift_tracks=load_actuator_tracks(meta.get("shift_motion",{}))
	for name in shift_tracks.keys():
		var frames=shift_tracks[name]
		var common=true
		for i in range(2,8):
			if not frames[1].is_equal_approx(frames[i]):
				common=false
				break
		if common:
			shared_shift_tracks[name]=frames
			shift_tracks.erase(name)
	ribbon_rig.setup(self,meta.ribbon_rig)
	tab_rig.setup(self)
	carriage_rig.setup(self)
	touch_lever.setup(self)
	keys=meta.keys
	stock_material=ShaderMaterial.new()
	stock_material.shader=Shader.new()
	stock_material.shader.code=PAPER_SHADER
	stock_material.set_shader_parameter("stock",Color("#f5f0df"))
	sheet=MeshInstance3D.new();sheet.material_override=stock_material;root.add_child(sheet)
	inspection.offset=DESK_FOCUS
	sync();travel=target_travel;update_camera()
func setup_grabs(desk):
	key_action.setup(self)
	grab_providers=[key_grabs,bail_grabs,paper_grabs,hood_grab,action_grabs,bottom_panels,page_stack]
	for provider in grab_providers:provider.setup(self,desk)
	inspection.setup(self)

func choose_grab(pos:Vector2)->Dictionary:
	var radius=minf(size.x,size.y)*.038
	var best={}
	for provider in grab_providers:
		var hit=provider.pick(pos,radius)
		if hit.is_empty():continue
		if best.is_empty() or hit.distance<best.distance:
			best=hit
			best.owner=provider
	# The two end releases share the same picking comparison as nearby fittings.
	for side in ["left","right"]:
		var label="Carriage release "+side
		var distance=camera.unproject_position(carriage_rig.point(label)).distance_to(pos)
		if distance<radius and distance<float(best.get("distance",INF)):
			best={"label":label,"distance":distance,"tip":"Hold and drag the carriage","side":side}
	return best

func finish_grab(cancelled:bool):
	var old=grab_owner
	grab_owner=null
	if old:old.finish(cancelled)
	mouse_default_cursor_shape=Control.CURSOR_ARROW

func sync():
	if not writer:return
	bottom_panels.update()
	var d=writer.data
	page_stack.sync()
	paper_in_machine=d.get("sheet_loaded",true)
	sheet.visible=paper_in_machine and (page_stack.airborne==null or page_stack.landing_time>=0.)
	target_travel=((writer.dimensions().x*.5-writer.MARGIN)/writer.PITCH-.5-writer.carriage_column())*.025
	if paper_in_machine and (d.half!=last_half or d.paper!=last_stock or sheet_pull!=last_sheet_pull or sheet_pull_side!=last_pull_side):
		last_sheet_pull=sheet_pull
		last_pull_side=sheet_pull_side
		last_half=d.half;last_stock=d.paper;update_sheet()
	if last_texture!=writer.texture:
		stock_material.set_shader_parameter("sheet_image",writer.texture);last_texture=writer.texture
# In Y/Z, the leading edge runs from the platen through the nip and
# around the back of the closed bail roller before rising toward the operator.
func paper_section(h:float,x:=0.,width:=Vector2(-1.,1.))->Vector2:
	const CENTER=Vector2(1.13,-.91)
	const R=.1519
	const NIP=1.315
	const EXIT=.34
	const WRAP=.0675
	const REAR=-2.43
	if h<REAR*R or h>bail_grabs.sheet_profile.EXIT_HEIGHT:return bail_grabs.sheet_profile.point(h,x,width)
	if h<=NIP*R:
		var a=h/R
		return CENTER+R*Vector2(sin(a),cos(a))
	var normal=Vector2(sin(NIP),cos(NIP))
	var roller=CENTER+(R+WRAP)*normal
	var run=h-NIP*R
	var a=maxf(EXIT,NIP-run/WRAP)
	var point=roller-WRAP*Vector2(sin(a),cos(a))
	return point+maxf(0.,run-(NIP-EXIT)*WRAP)*Vector2(cos(EXIT),-sin(EXIT))

func update_sheet():
	var dims=writer.dimensions();var pitch=.025/writer.PITCH
	var page_width=dims.x*pitch;var page_height=dims.y*pitch
	var above=(writer.BASE+float(writer.data.half)*writer.LEADING*.5)*pitch+sheet_pull
	var surf=SurfaceTool.new();surf.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Slice the registered page parallel to the axle. With a skewed sheet,
	# joining only its two side edges would cut chords through the platen.
	var skew=float(writer.data.paper_skew)
	var side=float(writer.data.paper_side)+sheet_pull_side
	var corners=PackedVector2Array()
	for uv in [Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]:
		corners.append(Vector2((uv.x-.5)*page_width,above-uv.y*page_height).rotated(skew)+Vector2(side,0))
	var heights:Array[float]=[]
	for corner in corners:
		if not corner.y in heights:heights.append(corner.y)
	heights.sort()
	bail_grabs.prepare_sheet(writer)
	bail_grabs.sheet_profile.prepare_leading(writer,heights[-1])
	const STRIPS=28
	var row_index:=0
	for band in range(heights.size()-1):
		var count=ceili((heights[band+1]-heights[band])/.012)
		for step in range(0 if band==0 else 1,count+1):
			var h=lerpf(heights[band],heights[band+1],step/float(count))
			var left_x=INF
			var right_x=-INF
			for edge in 4:
				var a=corners[edge]
				var b=corners[(edge+1)%4]
				if h<minf(a.y,b.y)-.000001 or h>maxf(a.y,b.y)+.000001:continue
				if is_equal_approx(a.y,b.y):
					left_x=minf(left_x,minf(a.x,b.x));right_x=maxf(right_x,maxf(a.x,b.x))
				else:
					var x=lerpf(a.x,b.x,clampf((h-a.y)/(b.y-a.y),0.,1.))
					left_x=minf(left_x,x);right_x=maxf(right_x,x)
			var width=Vector2(left_x,right_x)
			for strip in STRIPS+1:
				var x=lerpf(left_x,right_x,float(strip)/STRIPS)
				var local=(Vector2(x,h)-Vector2(side,0)).rotated(-skew)
				var section=paper_section(h,x,width)
				surf.set_uv(Vector2(local.x/page_width+.5,(above-local.y)/page_height))
				surf.add_vertex(Vector3(x,section.x,section.y))
			if row_index>0:
				for strip in STRIPS:
					var a=row_index*(STRIPS+1)+strip
					var b=a-STRIPS-1
					for index in [a,a+1,b+1,a,b+1,b]:surf.add_index(index)
			row_index+=1
	surf.generate_normals();sheet.mesh=surf.commit()
func update_camera():
	inspection.update(self)

func frame_machine():
	inspection.offset=Vector3.ZERO if cut else DESK_FOCUS
	zoom=3.25 if cut else OPERATOR_ZOOM
	tilt=.54 if cut else .64
	yaw=.42 if cut else .12
	update_camera()

func set_cut(value:bool):
	cut=value
	bottom_panels.update()
	for group in writer.meta.hood_groups:
		if groups.has(group):groups[group].visible=not value
	if groups.has("shell"):groups["shell"].visible=not value
	if groups.has("rear_carriage_cover"):groups.rear_carriage_cover.visible=not value
	frame_machine()
func load_actuator_tracks(source:Dictionary)->Dictionary:
	var tracks={}
	for name in source:
		if not groups.has(name):continue
		var poses:Array[Transform3D]=[]
		for raw in source[name]:
			var pose_basis=Basis(Vector3(raw[0],raw[1],raw[2]),Vector3(raw[3],raw[4],raw[5]),Vector3(raw[6],raw[7],raw[8]))
			poses.append(Transform3D(pose_basis,Vector3(raw[9],raw[10],raw[11])))
		tracks[name]=poses
	return tracks

func handle_drag_cancel(event)->bool:
	if suppress_cancel_orbit:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
			suppress_cancel_orbit=false
			return true
		if event is InputEventMouseMotion:return true
	var right=event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed
	var escape=event is InputEventKey and event.keycode==KEY_ESCAPE and event.pressed
	if not ((right or escape) and (grab_owner or carriage_dragging)):return false
	if grab_owner:finish_grab(true)
	if carriage_dragging:
		writer.slide_carriage(carriage_drag_origin)
		writer.data.margin_released=carriage_original_bypass
		finish_carriage_pointer()
		carriage_changed.emit()
	suppress_cancel_orbit=right
	return true

func reset_part(hit:Dictionary):
	if hit.is_empty():return
	if hit.has("side"):
		if release_sources.has("mouse"):finish_carriage_pointer()
		if not writer.data.center_locked:
			if writer.carriage_held():writer.slide_carriage(writer.data.left)
			else:writer.move_col(writer.data.left)
	elif hit.has("owner"):
		hit.owner.reset_default(hit.label)
	key_grabs.desk.changed()

func _input(event):
	if handle_drag_cancel(event):
		double_click_reset.forget()
		get_viewport().set_input_as_handled()
		return
	if grab_owner:
		if event is InputEventMouseMotion:
			double_click_reset.observe(make_input_local(event))
			grab_owner.drag(make_input_local(event).position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			finish_grab(false)
			double_click_reset.finish(self)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventKey and event.keycode==KEY_ESCAPE and event.pressed:
			finish_grab(true)
			get_viewport().set_input_as_handled()
			return
	if carriage_dragging or mouse_setter!="":
		if event is InputEventMouseMotion and carriage_dragging:
			double_click_reset.observe(make_input_local(event))
			drag_carriage(make_input_local(event).position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			finish_carriage_pointer()
			double_click_reset.finish(self)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.physical_keycode==KEY_SHIFT and not event.echo:
		var side=1 if event.location==KEY_LOCATION_RIGHT else 0
		shift_inputs[side]=1. if event.pressed else 0.
		if event.pressed:shift_pulse[side]=.09
		elif shift_bottom_contact:shift_pulse[side]=0.

func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		double_click_reset.forget()
		suppress_cancel_orbit=false
		shift_inputs=Vector2.ZERO;shift_pulse=Vector2.ZERO
		margin_key_held=false;margin_key_pulse=0.
		release_carriage_controls()

func update_shift_linkage(dt:float,typed_shift:float,typed_stroke:Dictionary={}):
	var keys_down=shift_inputs
	if key_grabs.desk:
		for side in 2:
			var analog:float=key_grabs.desk.wooting.shift_depth(side)
			if analog>=0.:
				keys_down[side]=analog
				shift_pulse[side]=0.
	if key_grabs.holding_shifter():
		var side=1 if key_grabs.held=="Shift lock" else key_grabs.shift_side()
		keys_down[side]=maxf(keys_down[side],key_grabs.depth)
	for side in 2:
		if shift_pulse[side]>0.:keys_down[side]=1.
		shift_pulse[side]=maxf(0.,shift_pulse[side]-dt)
	if action_grabs.held==action_grabs.GUIDE:keys_down.x=maxf(keys_down.x,action_grabs.depth)
	if key_latched:keys_down[clicked_shift]=1.
	var automatic=not writer.data.locked and keys_down==Vector2.ZERO
	if automatic:
		keys_down.x=typed_shift
	var targets=Vector3(keys_down.x,keys_down.y,1. if writer.data.locked else 0.)
	if key_grabs.held=="Shift lock":
		shift_sound_source="Shift lock"
	elif not is_equal_approx(keys_down.x,keys_down.y):
		shift_sound_source="Right shift" if keys_down.y>keys_down.x else "Left shift"
	elif targets.z>0. and not shift_bottom_contact:
		shift_sound_source="Shift lock"
	# Switching hands while Shift is down keeps the shared shaft against its stop.
	var depth=move_toward(shared_shift_depth,maxf(targets.x,maxf(targets.y,targets.z)),dt*22.)
	if depth!=shared_shift_depth:
		shift_excursion=maxf(shift_excursion,depth)
		if depth>=.94 and not shift_bottom_contact and key_grabs.desk:
			shift_bottom_contact=true
			shift_pulse=Vector2.ZERO
			key_grabs.desk.sound_shift_press(shift_sound_source,typed_stroke if automatic else {})
		if depth<shared_shift_depth:
			var speed=(shared_shift_depth-depth)/maxf(dt,.0001)
			if shared_shift_depth>.08 or shift_return_speed==0.:shift_return_speed=speed
			if depth<=.035 and shift_excursion>=.18:
				if key_grabs.desk:key_grabs.desk.sound_shift_release(shift_sound_source,shift_return_speed,shift_excursion)
				shift_bottom_contact=false
				shift_excursion=0.
				shift_return_speed=0.
			elif depth==0.:shift_excursion=0.
		shared_shift_depth=depth
		for name in shared_shift_tracks:
			var frames=shared_shift_tracks[name]
			groups[name].transform=frames[0].interpolate_with(frames[1],depth)
	for i in 3:shift_pose[i]=move_toward(shift_pose[i],targets[i],dt*22.)
	if shift_pose.is_equal_approx(last_shift_pose):return
	last_shift_pose=shift_pose
	for name in shift_tracks:
		var frames=shift_tracks[name]
		var low=frames[0].interpolate_with(frames[1],shift_pose.x).interpolate_with(frames[2].interpolate_with(frames[3],shift_pose.x),shift_pose.y)
		var high=frames[4].interpolate_with(frames[5],shift_pose.x).interpolate_with(frames[6].interpolate_with(frames[7],shift_pose.x),shift_pose.y)
		groups[name].transform=low.interpolate_with(high,shift_pose.z)

func set_margin_key(held:bool):
	# A tap between two rendered frames should still visibly depress the service key.
	if held and not margin_key_held:margin_key_pulse=.10
	margin_key_held=held

func tap_margin_key():
	margin_key_pulse=.14

func margin_press_pose(track:Array,index:int,fraction:float)->Transform3D:
	var step=mini(3,floori(fraction))
	return track[index+step].interpolate_with(track[index+step+1],fraction-step)

func update_margin_linkage(dt:float):
	var d=writer.data
	var center=(writer.dimensions().x*.5-writer.MARGIN)/writer.PITCH-.5
	var reference=writer.meta.get("margin_reference",[0,37])
	if groups.has("margin_stop:left"):
		groups["margin_stop:left"].position.x=travel+(float(d.left)-center-float(reference[0]))*.025
	if groups.has("margin_stop:right"):
		groups["margin_stop:right"].position.x=travel+(float(d.right)+1.-center-float(reference[1]))*.025
	var key_down=margin_key_held or margin_key_pulse>0. or key_grabs.held=="⇄"
	margin_key_pulse=maxf(0.,margin_key_pulse-dt)
	margin_press=move_toward(margin_press,1. if key_down else 0.,dt*16.)
	var bypassed=key_down or bool(d.get("margin_released",false))
	margin_bypass=move_toward(margin_bypass,1. if bypassed else 0.,dt*16.)
	var distance=clampf(center-travel/.025-float(d.right)-1.,margin_samples.front(),margin_samples.back())
	var state=Vector3(margin_press,margin_bypass,distance)
	if state.is_equal_approx(margin_pose):return
	margin_pose=state
	var column=0
	while column<margin_samples.size()-2 and distance>margin_samples[column+1]:column+=1
	var fraction=inverse_lerp(margin_samples[column],margin_samples[column+1],distance)
	var lo=column*10;var hi=lo+10
	for name in margin_tracks:
		var track:Array=margin_tracks[name]
		var a=margin_press_pose(track,lo,margin_press*4.).interpolate_with(margin_press_pose(track,lo+5,margin_press*4.),margin_bypass)
		var b=margin_press_pose(track,hi,margin_press*4.).interpolate_with(margin_press_pose(track,hi+5,margin_press*4.),margin_bypass)
		groups[name].transform=a.interpolate_with(b,fraction)
	# Fold the clearing finger forward of the paper at rest. Its working
	# end rejoins the sampled jam-release pose for contact with the typebar.
	var shaft=Vector3(0,1.013,-.768)
	for piece in ["formed clearing finger","clearing bow"]:
		var group="margin_part:Jam release | "+piece
		if groups.has(group):
			var angle=(1.40 if piece=="formed clearing finger" else .23)*(1.-smoothstep(0.,.82,margin_press))
			var rotation=Basis(Vector3.RIGHT,angle)
			groups[group].get_child(0).transform=Transform3D(rotation,shaft-rotation*shaft)
	for name in margin_flex:
		var track:Array=margin_flex[name]
		var step=mini(3,floori(margin_press*4.));var key_fraction=margin_press*4.-step
		var v=lo+step;var u=hi+step
		var a=lerpf(lerpf(track[v],track[v+1],key_fraction),lerpf(track[v+5],track[v+6],key_fraction),margin_bypass)
		var b=lerpf(lerpf(track[u],track[u+1],key_fraction),lerpf(track[u+5],track[u+6],key_fraction),margin_bypass)
		groups[name].get_child(0).set_blend_shape_value(0,lerpf(a,b,fraction))

func strike(e:Dictionary,slow=false,contact:=Callable()):
	if tab_rig.press(e.key,float(e.get("motion_duration",.105))):return
	motions.append({"e":e,"t":0.,"duration":1.45 if slow else float(e.get("motion_duration",.105)), "slow":slow,"contact":contact})
func _process(dt):
	if not writer or not active:return
	travel=target_travel if writer.carriage_held() else tab_rig.carriage_position(dt,lerpf(travel,target_travel,1.-exp(-dt*19)))
	if groups.has("carriage"):groups["carriage"].position.x=travel
	if groups.has("rear_carriage_cover"):groups.rear_carriage_cover.position.x=travel
	sheet.position.x=travel
	tab_rig.update(dt)
	update_margin_linkage(dt)
	var d=writer.data
	bail_angle=lerpf(bail_angle,-.74*float(d.bail_lift),1.-exp(-dt*14))
	return_phase=maxf(0.,return_phase-dt/return_duration)
	for tag in fittings:
		if not groups.has(tag):continue
		var part:Node3D=groups[tag];var pos:Vector3=fittings[tag]
		if not tag.begins_with("reel"):
			pos.x+=travel
			if tag=="return_lever":part.rotation.y=-.48*sin(PI*return_phase)
			if tag=="platen":part.rotation.x=float(d.half)*.0212/.1525
			if tag=="bail":part.rotation.x=bail_angle
			if tag.begins_with("roller"):
				var center:Vector3=fittings.bail
				var base:Vector3=fittings[tag]
				base.x=lerpf(-1.22,1.22,float(d.bail_left if tag=="roller_left" else d.bail_right))
				pos=center+(base-center).rotated(Vector3.RIGHT,bail_angle)+Vector3(travel,0,0)
				part.rotation.x=bail_angle+float(d.half)*.0212/.064
			part.position=pos
	var lift=0.
	var back=0.
	var working_stroke=0.
	var depths={}
	var l_travel=0.
	var shifted=0.
	var shifted_stroke={}
	for idx in range(motions.size()-1,-1,-1):
		var m=motions[idx]
		if not m.get("slow",false):m.duration=float(m.e.get("motion_duration",.105))
		m.t+=dt;var f=minf(1.,m.t/m.duration)
		if f>=.46 and m.get("contact",Callable()).is_valid():
			var impact:Callable=m.contact
			m.contact=Callable()
			impact.call()
		var k:String=m.e.key
		var v=sin(clampf(f/.46,0,1)*PI*.5) if f<.46 else pow(maxf(0.,1.-(f-.46)/.54),1.65)
		if m.e.get("miss",false):v*=.77
		if m.e.get("jam",false):v=minf(.71,v) if f<.46 else (.71 if writer.data.jammed else 0.)
		if writer.meta.bars.has(k):depths[k]=maxf(depths.get(k,0.),v)
		if k=="L":l_travel=maxf(l_travel,v)
		if m.e.has("ink"):
			working_stroke=maxf(working_stroke,v)
			if m.e.ink!="Stencil":
				var height=.130 if m.e.ink=="Red" else (.0775 if m.e.ink=="Split" else .065)
				lift=maxf(lift,height*v)
				back=maxf(back,.0465*v)
		if m.e.get("shift",false) and minf(1.,v*3.)>shifted:
			shifted=minf(1.,v*3.)
			shifted_stroke=m.e
		if groups.has("bar:"+k):
			var info=writer.meta.bars[k];var pivot:Node3D=groups["bar:"+k]
			pivot.quaternion=Quaternion(vec(info.axis).normalized(),info.angle*v)
		if groups.has("key:"+k):groups["key:"+k].position.y=-.041*v
		if f>=1. and not (m.e.get("jam",false) and writer.data.jammed):motions.remove_at(idx)
	if not grab_providers.is_empty():
		key_grabs.update(dt)
		action_grabs.update(dt)
		var analog_travel:float=key_grabs.apply_analog_pretravel(depths)
		l_travel=maxf(l_travel,float(depths.get("L",0.)))
		for caught in key_grabs.jam_keys:
			depths[caught]=key_grabs.jam_positions[caught]
		var manual=action_grabs.held!="" or action_grabs.returning
		var k=action_grabs.key if manual else key_grabs.drive_key()
		if writer.meta.bars.has(k):
			var depth=action_grabs.depth if manual else key_grabs.drive_depth()
			var bar=depth if manual else key_grabs.bar_depth()
			depths[k]=depth
			var info=writer.meta.bars[k]
			groups["bar:"+k].quaternion=Quaternion(vec(info.axis).normalized(),info.angle*bar)
			if k=="L":l_travel=depth
			analog_travel=maxf(analog_travel,bar)
		working_stroke=maxf(working_stroke,analog_travel)
		if d.ribbon!="Stencil":
			lift=maxf(lift,(.13 if d.ribbon=="Red" else (.0775 if d.ribbon=="Split" else .065))*analog_travel)
			back=maxf(back,.0465*analog_travel)
	ribbon_rig.update(dt,d,working_stroke)
	for mat in band_materials:
		mat.set_shader_parameter("lift",lift)
		mat.set_shader_parameter("back",back)
	update_shift_linkage(dt,shifted,shifted_stroke)
	shift_offset=.066*shared_shift_depth
	if groups.has("segment"):groups.segment.position.y=shift_offset
	for key in writer.meta.bars:groups["bar:"+key].position.y=float(writer.meta.bars[key].pivot[1])+shift_offset
	carriage_rig.update(dt)
	touch_lever.update(dt,int(d.touch_regulator),l_travel)
	if not grab_providers.is_empty():
		var trip=0.
		for key in depths:
			if key!="^ / "+char(96):trip=maxf(trip,depths[key])
		depths["@trip"]=trip
		key_action.update(depths,shift_offset/.066)
		key_action.highlight(action_grabs.key if cut and grab_owner==action_grabs else (key_grabs.drive_key() if cut and grab_owner==key_grabs else ""))
		page_stack.update(dt)
		paper_grabs.update(dt)
		bail_grabs.update(dt)
		hood_grab.update(dt)
	update_camera()

func hold_carriage(side:String,source:String,down:bool):
	if down:
		if release_sources.has(source):return
		release_sources[source]=side
	else:
		if not release_sources.has(source):return
		side=release_sources[source]
		release_sources.erase(source)
	var held=side in release_sources.values()
	writer.set_carriage_release(side,held)
	carriage_rig.set_control("Carriage release "+side,held)
	if not writer.carriage_held():carriage_dragging=false
	carriage_changed.emit()

func release_carriage_controls():
	finish_grab(true)
	finish_carriage_pointer()
	for source in release_sources.keys():
		hold_carriage(release_sources[source],source,false)

func finish_carriage_pointer():
	carriage_dragging=false
	if release_sources.has("mouse"):hold_carriage(release_sources["mouse"],"mouse",false)
	if mouse_setter!="":
		carriage_rig.set_control(mouse_setter,false)
		mouse_setter=""

func closest_carriage_control(pos:Vector2,radius:float)->String:
	var best=""
	for label in carriage_rig.LABELS:
		var p:Vector2=camera.unproject_position(carriage_rig.point(label))
		var distance=pos.distance_to(p)
		if distance<radius:
			best=label
			radius=distance
	return best

func over_carriage(pos:Vector2)->bool:
	var a=camera.unproject_position(carriage_rig.point("Carriage release left"))
	var b=camera.unproject_position(carriage_rig.point("Carriage release right"))
	var near=Geometry2D.get_closest_point_to_segment(pos,a,b)
	return pos.distance_to(near)<minf(size.x,size.y)*.13

func begin_carriage_drag(pos:Vector2):
	drag_position=pos
	carriage_drag_origin=writer.carriage_column()
	carriage_original_bypass=writer.data.margin_released
	carriage_dragging=true

func drag_carriage(pos:Vector2):
	if not writer.carriage_held():return
	var step=camera.unproject_position(Vector3.RIGHT*.025)-camera.unproject_position(Vector3.ZERO)
	if step.length_squared()>.01:
		var cells=(pos-drag_position).dot(step)/step.length_squared()
		writer.slide_carriage(writer.carriage_column()-cells)
		carriage_changed.emit()
	drag_position=pos

func _get_tooltip(at_position:Vector2)->String:
	if not camera or grab_providers.is_empty():return ""
	return choose_grab(at_position).get("tip","")

func _gui_input(event):
	if double_click_reset.observe(event):
		accept_event()
		return
	if handle_drag_cancel(event):
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		if grab_owner:
			finish_grab(false)
			accept_event()
		elif carriage_dragging:
			finish_carriage_pointer()
			accept_event()
		double_click_reset.finish(self)
		return
	if event is InputEventMouseMotion:
		if grab_owner:
			grab_owner.drag(event.position)
			accept_event()
		elif carriage_dragging:
			drag_carriage(event.position)
			accept_event()
		elif event.button_mask&MOUSE_BUTTON_MASK_RIGHT:
			if event.ctrl_pressed:
				inspection.pan(self,event.relative)
			else:
				yaw-=event.relative.x*.009
				var low=.02 if not cut and writer.data.show_floor and writer.data.camera_collision else -PI*.5
				tilt=clampf(tilt+event.relative.y*.008,low,PI*.5)
			update_camera();accept_event()
		else:
			mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND if not choose_grab(event.position).is_empty() else Control.CURSOR_ARROW
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and not grab_owner:
			zoom=clampf(zoom*(.91 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.1),.095,12.);update_camera();accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if grab_owner:finish_grab(true)
			var hit=choose_grab(event.position)
			if double_click_reset.press(self,event,hit):
				accept_event()
				return
			if hit.has("side"):
				hold_carriage(hit.side,"mouse",true)
				begin_carriage_drag(event.position)
			elif writer.carriage_held() and over_carriage(event.position) and (hit.is_empty() or hit.label=="Loose sheet"):
				begin_carriage_drag(event.position)
			elif hit.has("owner"):
				grab_owner=hit.owner
				grab_owner.begin(hit.label,event.position,event.shift_pressed)
			else:return
			mouse_default_cursor_shape=Control.CURSOR_DRAG
			accept_event()

func read_vectors(file:FileAccess,count:int)->PackedVector3Array:
	var src=file.get_buffer(count*12).to_float32_array()
	var dst=PackedVector3Array()
	dst.resize(count)
	for i in count:dst[i]=Vector3(src[i*3],src[i*3+1],src[i*3+2])
	return dst








