extends RefCounted
## Paper registration, platen clutch, return, selector and table finger controls.
const SETTINGS={"paper_loose":false,"free_platen":false,"platen_half":0.,"ratchet_half":0.,"grip_half":0.,"paper_side":0.,"paper_skew":0.,"edge_guide_mm":-112.3}
const HINTS={"Left platen knob":"Click above or below the axle for one detent. Drag vertically to roll, or pull outward to disengage the clutch.","Right platen knob":"Click above or below the axle for one detent, or drag to turn the platen.","Line spacing selector":"Drag through single, double, triple, and white-dot free roll.","Carriage return":"Push the palm spoon to index the paper, then carry the carriage home.","Paper release":"Pull the paddle to release the pressure rollers. Push it back to grip.","Paper edge guide":"Slide the paper fence across the table.","Loose sheet":"Drag to reposition the released sheet. Pull either end clear, carry it to the tray, and release to stack it. Shift-drag to straighten."}
var machine
var desk
var spec:Dictionary
var tracks={}
var active=""
var origin=Vector2.ZERO
var started={}
var clutch:=0.
var release:=0.
var selector:=0.
var sweep:=0.
var travel_velocity=preload("res://TravelVelocity.gd").new()
var hand_position:=0.
var held_sweep:=0.
var registered=Vector2(INF,INF)
var sheet_mesh
var sheet_faces=PackedVector3Array()
var picked_rear:=false
var withdrawing_rear:=false
var carrying:=false
const FEED_FIELDS=["half","platen_half","ratchet_half","grip_half","col"]
var gesture_delta={}
var stock_token
var initial_raw=0.
var fed_half=0.
var returned=false
var dragged=false
var shifting=false

static func defaults(data:Dictionary):
	for k in SETTINGS:data[k]=SETTINGS[k]

static func migrate(data:Dictionary)->bool:
	for k in SETTINGS:
		if not data.has(k):
			data[k]=data.get("half",0) if k in ["platen_half","ratchet_half","grip_half"] else SETTINGS[k]
		if SETTINGS[k] is bool:
			if not data[k] is bool:return false
		elif typeof(data[k]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(data[k])):return false
	if absf(data.paper_skew)>.251 or absf(data.paper_side)>.801 or data.edge_guide_mm < -124.001 or data.edge_guide_mm > -41.999:return false
	return true

static func change_stock(data:Dictionary,old:Dictionary):
	for k in ["edge_guide_mm","free_platen","spacing"]:
		if old.has(k):data[k]=old[k]

static func turn(writer,amount:float,coupled:=true):
	var d=writer.data
	if d.paper_loose or not d.get("sheet_loaded",true):
		d.platen_half+=amount
	else:
		var target=clampf(float(d.half)+amount,0.,writer.max_half())
		amount=target-float(d.half)
		d.half=target
		d.grip_half+=amount
		d.platen_half+=amount
	if coupled:d.ratchet_half+=amount

static func sheet_point(writer,flat:Vector2)->Vector2:
	return flat.rotated(float(writer.data.paper_skew))+Vector2(writer.data.paper_side,0)

static func material_pixel(writer,pixel:Vector2)->Vector2:
	var pitch=.025/float(writer.PITCH)
	var base=writer.BASE+float(writer.data.half)*writer.LEADING*.5
	var translated=Vector2((pixel.x-writer.dimensions().x*.5)*pitch,(base-pixel.y)*pitch)
	var local=(translated-Vector2(writer.data.paper_side,0)).rotated(-float(writer.data.paper_skew))
	return Vector2(local.x/pitch+writer.dimensions().x*.5,base-local.y/pitch)

static func register_strike(writer,e:Dictionary):
	if is_zero_approx(writer.data.paper_side) and is_zero_approx(writer.data.paper_skew):return
	var nominal=Vector2(writer.MARGIN+(e.col+.5)*writer.PITCH,writer.BASE+float(e.half)*writer.LEADING*.5)
	var delta=material_pixel(writer,nominal)-nominal
	e.dx+=delta.x
	e.dy+=delta.y

func setup(host,owner):
	machine=host
	desk=owner
	spec=host.writer.meta.paper_grabs
	for field in spec.tracks:tracks[field]=host.load_actuator_tracks(spec.tracks[field])

func target(label:String)->Vector3:
	var t:Array=spec.targets[label]
	return machine.groups[t[0]].transform*machine.vec(t[1])

func sheet_hit(pos:Vector2)->bool:
	if not machine.sheet.visible or not machine.writer.data.paper_loose or machine.sheet.mesh==null:return false
	var from=machine.camera.project_ray_origin(pos)
	var ray=machine.camera.project_ray_normal(pos)
	if sheet_mesh!=machine.sheet.mesh:
		sheet_mesh=machine.sheet.mesh
		sheet_faces=sheet_mesh.get_faces()
	var verts=sheet_faces
	var local=machine.sheet.to_local(from)
	var direction=machine.sheet.global_transform.basis.inverse()*ray
	if machine.sheet.mesh.get_aabb().intersects_ray(local,direction)==null:return false
	var closest=INF
	for i in range(0,verts.size(),3):
		var p=Geometry3D.ray_intersects_triangle(local,direction,verts[i],verts[i+1],verts[i+2])
		if p==null:continue
		var d=local.distance_squared_to(p)
		if d<closest:
			closest=d
			# The page can fold back over itself. UV identifies which end the
			# operator touched even when both layers occupy the same screen pixel.
			var arrays=sheet_mesh.surface_get_arrays(0)
			var uv:Vector2=arrays[Mesh.ARRAY_TEX_UV][arrays[Mesh.ARRAY_INDEX][i]]
			var w=machine.writer
			picked_rear=(w.BASE+float(w.data.half)*w.LEADING*.5-uv.y*w.dimensions().y)*.025/w.PITCH < -.2
	return closest<INF

func pick(pos:Vector2,radius:float)->Dictionary:
	var best={}
	for label in spec.targets:
		var p=machine.camera.unproject_position(target(label))
		var distance=p.distance_to(pos)
		if distance<radius:
			best={"label":label,"distance":distance,"tip":HINTS[label]}
			radius=distance
	if best.is_empty() and sheet_hit(pos):
		return {"label":"Loose sheet","distance":radius,"tip":HINTS["Loose sheet"]}
	return best

func begin(label:String,pos:Vector2,shifted:bool):
	if not HINTS.has(label):return
	var d=machine.writer.data
	active=label
	withdrawing_rear=picked_rear
	carrying=false
	hand_position=0.
	travel_velocity.reset(hand_position)
	origin=pos
	started={"col":int(d.col),"half":float(d.half),"platen":float(d.platen_half),"ratchet":float(d.ratchet_half),"side":float(d.paper_side),"skew":float(d.paper_skew),"guide":float(d.edge_guide_mm),"white":bool(d.free_platen),"spacing":int(d.spacing),"loose":bool(d.paper_loose)}
	stock_token=machine.writer.raster
	started.bypass=d.margin_released
	gesture_delta.clear()
	for k in FEED_FIELDS:gesture_delta[k]=0.
	fed_half=0.
	held_sweep=0.
	returned=false
	dragged=false
	shifting=shifted
	clutch=1. if label=="Left platen knob" and shifted else 0.
	initial_raw=float(d.platen_half)

func turn_knob(w, amount:float, touch:float=-1.):
	var previous:int=roundi(w.data.ratchet_half)
	turn(w,amount,clutch<.5)
	if clutch<.5 and not w.data.free_platen and roundi(w.data.ratchet_half)!=previous:
		desk.sound_platen(touch)

func screen_axis(axis:Vector3)->Vector2:
	return machine.camera.unproject_position(axis)-machine.camera.unproject_position(Vector3.ZERO)

func change_selector(value:int):
	var w=machine.writer
	var d=w.data
	if value==3:
		d.free_platen=true
	else:
		if d.free_platen:turn(w,roundf(d.ratchet_half)-d.ratchet_half)
		d.free_platen=false
		d.spacing=value+1

func fence():
	var w=machine.writer
	var d=w.data
	var half_width=float(w.dimensions().x)*.025/w.PITCH*.5
	var fence_min=float(d.edge_guide_mm)*.01+half_width*cos(float(d.paper_skew))
	# The fence only registers the sheet while the sheet can slide in the nip.
	if d.paper_loose:d.paper_side=clampf(maxf(d.paper_side,fence_min),-.8,.8)

func drag(pos:Vector2):
	if active.is_empty():return
	if machine.writer.raster!=stock_token:finish(true);return
	if carrying:
		machine.page_stack.carry_to(pos)
		return
	var w=machine.writer
	var d=w.data
	var delta=pos-origin
	var scale=maxf(1.,screen_axis(Vector3.UP).length())
	var horizontal=screen_axis(Vector3.RIGHT)
	var across=delta.dot(horizontal)/maxf(1.,horizontal.length_squared())
	var down=delta.y/scale
	if delta.length()>3.:dragged=true
	var before={}
	for field in FEED_FIELDS:before[field]=d[field]
	match active:
		"Carriage return":
			if w.carriage_held() or d.center_locked:return
			var hand=maxf(0.,across)
			hand_position=hand
			travel_velocity.record(hand_position)
			held_sweep=clampf(hand/.16,0.,1.)
			var feed=2.*started.spacing*clampf((held_sweep-.08)/.78,0.,1.)
			if feed>fed_half:
				turn(w,feed-fed_half)
				fed_half=feed
			if hand>=.16:
				var end=w.rail_left() if w.margin_held else int(d.left)
				var travel_to=roundi(move_toward(float(started.col),float(end),(hand-.16)/.025))
				w.move_col(mini(int(d.col),travel_to) if end<=started.col else maxi(int(d.col),travel_to))
				if not returned:desk.sound_carriage_return(int(started.col)-end,maxf(0.,travel_velocity.speed()))
				d.margin_released=false
				returned=true
		"Left platen knob","Right platen knob":
			if active=="Left platen knob" and (shifting or across < -.036):clutch=1.
			var wanted=initial_raw-down/.055
			hand_position=wanted-initial_raw
			travel_velocity.record(hand_position)
			# Travel in ratchet detents per second, sampled before quantization.
			var touch=clampf(inverse_lerp(2.,24.,absf(travel_velocity.speed())),0.,1.)
			if not d.free_platen and clutch<.5:wanted=initial_raw+roundf(wanted-initial_raw)
			turn_knob(w,wanted-initial_raw-gesture_delta.platen_half,touch)
		"Line spacing selector":
			var along=screen_axis(Vector3(0,0,-.037))
			var index=3 if started.white else int(started.spacing)-1
			if along.length_squared()>1.:
				change_selector(clampi(index+roundi(delta.dot(along)/along.length_squared()),0,3))
		"Paper release":
			if absf(down)>.035:
				d.paper_loose=down>0.
		"Paper edge guide":
			d.edge_guide_mm=clampf(started.guide+across*100.,-124.,-42.)
			fence()
		"Loose sheet":
			if not d.paper_loose:return
			if shifting:d.paper_skew=clampf(started.skew+across*.8,-.25,.25)
			else:
				var desired_side=float(started.side)+across
				d.paper_side=clampf(desired_side,-.8,.8)
				var half_step=w.LEADING*.5*.025/w.PITCH
				var feed=down if withdrawing_rear else -down
				var desired=float(d.half)-gesture_delta.half+feed/half_step
				var scale_to_world=.025/w.PITCH
				var width=w.dimensions().x*scale_to_world
				var height=w.dimensions().y*scale_to_world
				var skew_edge=absf(sin(float(d.paper_skew)))*width*.5
				var base=w.BASE*scale_to_world
				var front=(height+skew_edge+.23-base)/half_step
				var rear=(-.39-skew_edge-base)/half_step
				var side_limit=1.39+width*.5+absf(sin(float(d.paper_skew)))*height
				var over_edge=desired>=front or desired<=rear or absf(desired_side)>=side_limit
				desired=clampf(desired,rear,front)
				d.half=clampf(desired,0.,w.max_half())
				machine.sheet_pull=(desired-d.half)*half_step
				machine.sheet_pull_side=clampf(desired_side,-side_limit,side_limit)-d.paper_side
				if over_edge or (delta.length()>35. and machine.page_stack.over_tray(pos)):
					machine.sync()
					machine.page_stack.capture_sheet(pos)
					carrying=true
			fence()
	for field in FEED_FIELDS:gesture_delta[field]+=float(d[field])-float(before[field])
	desk.changed()

func finish(cancelled:bool=false):
	if active.is_empty():return
	var w=machine.writer
	var d=w.data
	var same_sheet=w.raster==stock_token
	var place=carrying and not cancelled and same_sheet
	if carrying and not place:machine.page_stack.clear_air()
	carrying=false
	machine.sheet_pull=0.
	machine.sheet_pull_side=0.
	if cancelled and same_sheet:
		# Return only the displacement contributed by this gesture. Keyboard
		# line feeds and typed escapement can coexist with an operating hand.
		for field in FEED_FIELDS:
			if is_zero_approx(gesture_delta[field]):continue
			var restored=float(d[field])-gesture_delta[field]
			if field=="col":w.move_col(roundi(restored))
			elif field=="half":d.half=clampf(restored,0.,w.max_half())
			else:d[field]=restored
		match active:
			"Carriage return":
				if int(d.col)==started.col:d.margin_released=started.bypass
			"Line spacing selector":
				d.free_platen=started.white
				d.spacing=started.spacing
			"Paper release":d.paper_loose=started.loose
			"Paper edge guide":
				d.edge_guide_mm=started.guide
				d.paper_side=started.side
			"Loose sheet":
				d.paper_side=started.side
				d.paper_skew=started.skew
	elif not cancelled and same_sheet and not dragged:
		match active:
			"Carriage return":desk.type_char("\n")
			"Left platen knob","Right platen knob":
				var axle=machine.camera.unproject_position(target(active))
				turn_knob(w,1. if origin.y<=axle.y else -1.)
			"Paper release":d.paper_loose=not d.paper_loose
			"Line spacing selector":change_selector(0 if d.free_platen else int(d.spacing)%4)
	if active=="Carriage return" and not cancelled and dragged and same_sheet:
		# A partial pawl throw settles in the nearest of the two valleys per line.
		turn(w,roundf(fed_half)-fed_half)
	active=""
	stock_token=null
	clutch=0.
	held_sweep=0.
	if place:
		if not desk.finish_page():machine.page_stack.clear_air()
	desk.changed()

func reset_default(label:String):
	var w=machine.writer
	var d=w.data
	match label:
		"Left platen knob","Right platen knob":
			# Rotate the common axle to its initial registration. A released
			# sheet stays put, just as when the knob is turned by hand.
			turn(w,-float(d.platen_half))
			clutch=0.
		"Line spacing selector":change_selector(0)
		"Carriage return":
			held_sweep=0.
			sweep=0.
			machine.return_phase=0.
		"Paper release":d.paper_loose=false
		"Paper edge guide":
			d.edge_guide_mm=SETTINGS.edge_guide_mm
			fence()
		"Loose sheet":
			d.paper_side=0.
			d.paper_skew=0.
			d.half=0.
			fence()
		_:return
	desk.changed()

func track_pose(poses:Array,value:float)->Transform3D:
	var sample=clampf(value,0.,float(poses.size()-1))
	var lower=mini(floori(sample),poses.size()-2)
	return poses[lower].interpolate_with(poses[lower+1],sample-lower)

func spin(pivot:Vector3,angle:float)->Transform3D:
	var rot=Basis(Vector3.RIGHT,angle)
	return Transform3D(rot,pivot-rot*pivot)

func update(dt:float):
	var d=machine.writer.data
	if active in ["Carriage return","Left platen knob","Right platen knob"]:
		travel_velocity.record(hand_position)
	var next_return=held_sweep if active=="Carriage return" else sin(PI*machine.return_phase)
	sweep=move_toward(sweep,next_return,dt*16.)
	release=move_toward(release,float(d.paper_loose),dt*12.)
	selector=move_toward(selector,3. if d.free_platen else float(d.spacing)-1.,dt*12.)
	var factors={"release":release*4.,"clutch":clutch*4.,"selector":selector,"return":sweep*4.,"pawl":sweep*float(d.spacing)*4.}
	var transforms={}
	for channel in factors:
		for g in tracks[channel]:
			var p=track_pose(tracks[channel][g],factors[channel])
			transforms[g]=transforms.get(g,Transform3D.IDENTITY)*p
	for g in spec.parts:
		var p:Transform3D=transforms.get(g,Transform3D.IDENTITY)
		if g in spec.guide:p.origin.x+=(float(d.edge_guide_mm)+112.3)*.01
		if spec.rotors.has(g):
			var row:Array=spec.rotors[g]
			var amount=d.ratchet_half if row[0]=="wheel" else (d.grip_half if row[0]=="roller" else d.platen_half)
			p=p*spin(machine.vec(row[1]),float(amount)*float(row[2]))
		p.origin.x+=machine.travel
		machine.groups[g].transform=p
	if machine.groups.has("platen"):machine.groups.platen.rotation.x=-float(d.platen_half)*TAU/45.
	var reg=Vector2(d.paper_side,d.paper_skew)
	if reg!=registered:
		registered=reg
		machine.update_sheet()
