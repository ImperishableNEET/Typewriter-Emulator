extends RefCounted
## Desk out-tray, loose stock and the airborne sheet between platen and tray.
const CENTER=Vector3(2.96,0.,.10)
const VISIBLE_PAGES=7
const TRAY_SIZE=Vector2(2.16,2.77)
const EMPTY_FEED="Empty paper table"
const STACK_LABEL="Finished page "
const CARRY_VERTEX="""
uniform mat4 landing;
uniform vec2 page_size;
uniform vec3 pickup_offset;
uniform float placement;
void vertex() {
	vec3 placed_vertex=(landing*vec4((UV.x-.5)*page_size.x,0.,(UV.y-.5)*page_size.y,1.)).xyz;
	VERTEX=mix(VERTEX+pickup_offset,placed_vertex,placement);
	VERTEX.y+=0.33*sin(3.14159*placement);
	NORMAL=normalize(mix(NORMAL,vec3(0.,1.,0.),placement));
}
"""
var m
var desk
var tray:Node3D
var leaves:Array=[]
var count:=-1
var top_record
var picked:=""
var down:=Vector2.ZERO
var dragged:=false
var airborne:MeshInstance3D
var air_material:ShaderMaterial
var pickup_pixel:=Vector2.ZERO
var landing_time:=-1.
var previous_loaded:=true

func material(color:Color,metal:=0.)->StandardMaterial3D:
	var mat=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.metallic=metal
	mat.roughness=.72
	return mat

func box(parent:Node3D,size:Vector3,center:Vector3,mat:Material):
	var mesh=BoxMesh.new()
	mesh.size=size
	var node=MeshInstance3D.new()
	node.mesh=mesh
	node.position=center
	node.material_override=mat
	parent.add_child(node)

func setup(machine,controller):
	m=machine
	desk=controller
	tray=Node3D.new()
	tray.position=CENTER
	m.root.add_child(tray)
	var enamel=material(Color("#425348"),.27)
	var felt=material(Color("#687568"))
	var nickel=material(Color("#afa988"),.65)
	box(tray,Vector3(TRAY_SIZE.x,.025,TRAY_SIZE.y),Vector3(0,.013,0),enamel)
	box(tray,Vector3(TRAY_SIZE.x-.035,.008,TRAY_SIZE.y-.035),Vector3(0,.030,0),felt)
	for side in [-1.,1.]:
		box(tray,Vector3(.022,.052,TRAY_SIZE.y),Vector3(side*(TRAY_SIZE.x-.022)*.5,.046,0),enamel)
	box(tray,Vector3(TRAY_SIZE.x,.073,.022),Vector3(0,.055,-TRAY_SIZE.y*.5+.011),enamel)
	# The lowered front edge leaves enough room to lift a sheet by a corner.
	box(tray,Vector3(TRAY_SIZE.x,.012,.018),Vector3(0,.032,TRAY_SIZE.y*.5-.009),nickel)
	sync()

func make_leaf(index:int,level:int):
	var image:Image=m.writer.finished_image(index)
	if image==null:return
	var page_size=Vector2(image.get_size())*.025/m.writer.PITCH
	var sheet=MeshInstance3D.new()
	var mesh=PlaneMesh.new()
	mesh.size=page_size
	sheet.mesh=mesh
	var mat=m.stock_material.duplicate()
	# Keep full-resolution records in the writer; only a desktop-sized texture
	# is needed on the tray, and each visible sheet owns its texture.
	var thumbnail=image.duplicate()
	thumbnail.resize(maxi(1,image.get_width()/2),maxi(1,image.get_height()/2),Image.INTERPOLATE_LANCZOS)
	mat.set_shader_parameter("sheet_image",ImageTexture.create_from_image(thumbnail))
	sheet.material_override=mat
	var depth=minf(float(index-level),60.)*.001
	sheet.position=Vector3(sin(1.8*index)*.015,.039+depth+level*.003,cos(.8*index)*.014)
	sheet.rotation.y=sin(float(index)*2.3)*.009
	tray.add_child(sheet)
	leaves.append({"node":sheet,"index":index,"size":page_size})

func sync():
	if not tray:return
	var w=m.writer
	var archive:Array=w.data.get("finished_pages",[])
	var loaded:bool=w.data.get("sheet_loaded",true)
	var n=archive.size()
	var latest=archive.back() if n else null
	if n==count and is_same(latest,top_record):
		previous_loaded=loaded
		return
	var dropped=count>=0 and n==count+1 and previous_loaded and not loaded
	if dropped and not airborne:capture_sheet(Vector2.ZERO)
	if not dropped and airborne and landing_time>=0.:clear_air()
	for leaf in leaves:leaf.node.queue_free()
	leaves.clear()
	for i in range(maxi(0,n-VISIBLE_PAGES),n):make_leaf(i,leaves.size())
	count=n
	top_record=latest
	previous_loaded=loaded
	if dropped and airborne and not leaves.is_empty():
		var last:Dictionary=leaves.back()
		last.node.visible=false
		air_material.set_shader_parameter("landing",airborne.global_transform.affine_inverse()*last.node.global_transform)
		landing_time=0.
	elif not dropped and airborne:clear_air()

func capture_sheet(pixel:Vector2):
	if not m.sheet.mesh:return
	clear_air()
	airborne=MeshInstance3D.new()
	airborne.mesh=m.sheet.mesh
	airborne.transform=m.sheet.transform
	m.root.add_child(airborne)
	air_material=ShaderMaterial.new()
	air_material.shader=Shader.new()
	air_material.shader.code=m.PAPER_SHADER+CARRY_VERTEX
	var tex=m.stock_material.get_shader_parameter("sheet_image")
	air_material.set_shader_parameter("sheet_image",tex)
	air_material.set_shader_parameter("stock",Color("#f5f0df"))
	var dims=Vector2(tex.get_width(),tex.get_height()) if tex else Vector2(m.writer.dimensions())
	air_material.set_shader_parameter("page_size",dims*.025/m.writer.PITCH)
	air_material.set_shader_parameter("landing",Transform3D.IDENTITY)
	airborne.material_override=air_material
	airborne.extra_cull_margin=8.
	pickup_pixel=pixel
	m.sheet.visible=false

func carry_to(pixel:Vector2):
	if not airborne or landing_time>=0.:return
	var offset=m.camera.project_position(pixel,1.)-m.camera.project_position(pickup_pixel,1.)
	air_material.set_shader_parameter("pickup_offset",offset)

func clear_air():
	if airborne:
		airborne.queue_free()
		airborne=null
		air_material=null
	landing_time=-1.
	if not leaves.is_empty():leaves.back().node.visible=true

func update(dt:float):
	if not airborne or landing_time<0.:return
	landing_time+=dt
	var t=clampf(landing_time/.42,0.,1.)
	air_material.set_shader_parameter("placement",smoothstep(0.,1.,t))
	if t==1.:clear_air()

func plane_hit(pos:Vector2,frame:Transform3D,size:Vector2)->bool:
	var inverse=frame.affine_inverse()
	var origin=inverse*m.camera.project_ray_origin(pos)
	var direction=inverse.basis*m.camera.project_ray_normal(pos)
	if absf(direction.y)<.0001:return false
	var t=-origin.y/direction.y
	if t<0.:return false
	var p=origin+t*direction
	return absf(p.x)<=size.x*.5 and absf(p.z)<=size.y*.5

func over_tray(pos:Vector2)->bool:
	return tray and plane_hit(pos,tray.global_transform,TRAY_SIZE)

func pick(pos:Vector2,radius:float)->Dictionary:
	if not tray:return {}
	for i in range(leaves.size()-1,-1,-1):
		var leaf:Dictionary=leaves[i]
		if leaf.node.visible and plane_hit(pos,leaf.node.global_transform,leaf.size):
			var number=int(leaf.index)+1
			return {"label":STACK_LABEL+str(number),"distance":radius*.96,"tip":"Read finished page %d"%number}
	if not m.writer.data.get("sheet_loaded",true):
		var frame=Transform3D(Basis(Vector3.RIGHT,.71),Vector3(m.travel,1.23,-1.24))
		if plane_hit(pos,frame,Vector2(2.10,.43)):
			return {"label":EMPTY_FEED,"distance":radius*.94,"tip":"Click the empty paper table to load a fresh sheet."}
	return {}

func begin(label:String,pos:Vector2,_shifted:bool):
	picked=label
	down=pos
	dragged=false

func drag(pos:Vector2):
	if down.distance_to(pos)>6.:dragged=true

func finish(cancelled:bool):
	var label=picked
	picked=""
	if cancelled or dragged:return
	if label==EMPTY_FEED and not m.writer.data.sheet_loaded:desk.load_next_sheet()
	elif label.begins_with(STACK_LABEL):desk.browse_page(int(label.trim_prefix(STACK_LABEL))-1)

func reset_default(_label:String):
	pass

