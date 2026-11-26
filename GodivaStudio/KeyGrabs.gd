extends RefCounted
## Mouse-operated keys, selector detents, and typebars lodged at the printing point.
const SWATCHES=["Stencil","Blue","Yellow","Red"]
const MODES=["Stencil","Black","Split","Red"]
const STRIKE_DEPTH=.94
const DEAD_ZONE=3.
const DWELL=.18
const SLUG="Jammed typebar "
const RIBBON_LEVER="Ribbon selector lever"
var m
var desk
var held=""
var start=Vector2.ZERO
var shifted_click=false
var used_shift=false
var shift_was_locked=false
var at_grab={}
var depth=0.
var elapsed=0.
var moved=false
var committed=false
var return_key=""
var return_depth=0.
var returning_direct=false
var pointer_strength=-1.
var travel_velocity=preload("res://TravelVelocity.gd").new()
var ribbon_handle=""
var cap_groups={}
var service_tracks={}
var service_prevs={}
var service_recovery={}
var live_service={}
var live_print_keys={}
var print_bindings={}
var space_trip=.81
var type_tips={}
var jam_keys=[]
var jam_positions={}
var grabbed_bar_point=Vector3.ZERO
var jam_origin=0.
var cleared=false
var ribbon_lever_rest=Vector3.ZERO
var tab_keys=["+","−","···","TAB"]

func setup(machine,desktop):
	m=machine
	desk=desktop
	if m.writer.meta.has("key_grabs"):
		var manifest:Dictionary=m.writer.meta.key_grabs
		for key in ["Space","↶"]:
			service_tracks[key]=m.load_actuator_tracks(manifest[key])
			service_prevs[key]=-1.
			service_recovery[key]=false
		space_trip=float(manifest.space_trip)
	for name in m.groups:
		if name.begins_with("ribbon_control:Selector | nickel finger"):
			ribbon_handle=name
			ribbon_lever_rest=m.parts[name].get_aabb().get_center()
		elif name.begins_with("shift_part:Key ") and not name.begins_with("shift_part:Key shoes") and " | " in name:
			var label:String=name.split(" | ")[1].get_slice(".",0)
			cap_groups[label]=name
		elif name.begins_with("key:"):
			cap_groups[name.substr(4)]=name
	# The cast type face is a separate surface within each bar's exported mesh.
	for part in m.writer.meta.parts:
		var group:String=part[0]
		if not group.begins_with("bar:") or not "cast type alloy" in str(part[1]):continue
		var mesh:ArrayMesh=m.parts[group]
		var index=0
		for other in m.writer.meta.parts:
			if other==part:break
			if other[0]==group:index+=1
		var vertices:PackedVector3Array=mesh.surface_get_arrays(index)[Mesh.ARRAY_VERTEX]
		var center=Vector3.ZERO
		for v in vertices:center+=v
		type_tips[group.substr(4)]=center/vertices.size()-m.vec(m.writer.meta.bars[group.substr(4)].pivot)

func shifted()->bool:return held in ["Left shift","Right shift"]
func holding_shifter()->bool:return shifted() or held=="Shift lock"
func shift_strength()->float:
	return measured_strength() if holding_shifter() and moved else -1.
func shift_side()->int:return int(held=="Right shift")

func shift_character(ch:String)->String:
	if ((holding_shifter() and depth>=STRIKE_DEPTH) or (m.action_grabs.held==m.action_grabs.GUIDE and m.action_grabs.depth>=.94)) and m.writer.mappings.has(ch):
		used_shift=true
		return m.writer.pair_for(m.writer.mappings[ch][0])[1]
	return ch

func point(key:String)->Vector3:
	if key=="Space":
		var mesh=m.parts.get("key:Space")
		return m.groups["key:Space"].transform*mesh.get_aabb().get_center() if mesh else Vector3(0,.25,1.53)
	if key==RIBBON_LEVER:return m.groups[ribbon_handle].global_transform*ribbon_lever_rest
	if key.begins_with(SLUG):
		var name=key.trim_prefix(SLUG)
		return bar_at(name,type_tips[name],jam_positions.get(name,.71))
	var rest=m.vec(m.keys[key])
	if key.begins_with("Ribbon index "):return rest+m.hood_grab.root.position
	if key.begins_with("Ribbon index ") and m.groups.has("hood"):return m.groups.hood.global_transform*rest
	if key=="Touch regulator":return m.groups[m.writer.meta.touch_rig.handle].transform*rest
	if key.begins_with("Ribbon guide "):
		var group="ribbon_control:Manual ribbon | "+key.get_slice(" ",2).capitalize()+" side-guide finger tab"
		return m.groups[group].transform*rest
	if cap_groups.has(key):return m.groups[cap_groups[key]].transform*rest
	return rest

func screen(world:Vector3)->Vector2:return m.camera.unproject_position(world)

func guide_exposed()->bool:
	return m.cut or (m.get("hood_grab")!=null and m.hood_grab.lift>.25)

func pick(pos:Vector2,radius:float)->Dictionary:
	var best=""
	var limit=radius
	for key in m.keys:
		if key.begins_with("Ribbon guide") and not guide_exposed():continue
		if key.begins_with("Ribbon index") and m.cut:continue
		var dist=pos.distance_to(screen(point(key)))
		if dist<limit:best=key;limit=dist
	if not m.cut and ribbon_handle!="":
		var dist=pos.distance_to(screen(point(RIBBON_LEVER)))
		if dist<limit:best=RIBBON_LEVER;limit=dist
	var space=point("Space")
	var closest=Geometry2D.get_closest_point_to_segment(pos,screen(space-Vector3.RIGHT*.70),screen(space+Vector3.RIGHT*.70))
	var gap=pos.distance_to(closest)
	if gap<limit:best="Space";limit=gap
	if m.writer.data.jammed:
		refresh_jam()
		for key in jam_keys:
			var q=float(jam_positions[key])
			var inner=screen(bar_at(key,type_tips[key]*(.38 if m.cut else .82),q))
			var outer=screen(bar_at(key,type_tips[key],q))
			var dist=pos.distance_to(Geometry2D.get_closest_point_to_segment(pos,inner,outer))
			if dist<minf(limit,12.):best=SLUG+key;limit=dist
	if best=="":return {}
	var tip="Press "+best+" or drag down to feel the key travel"
	if best.begins_with(SLUG):tip="Pull the caught typebar back toward its basket"
	elif best=="Shift lock":tip="Drag to the end of travel to latch the basket"
	elif best in ["Left shift","Right shift"]:tip="Hold to shift, or drag to move the basket through its travel"
	elif best=="⇄":tip="Hold for margin override or press to release caught typebars"
	elif best=="Touch regulator":tip="Drag the touch lever through its four detents"
	elif best==RIBBON_LEVER or best.begins_with("Ribbon index "):tip="Drag the ribbon selector to a colored mark"
	elif best.begins_with("Ribbon guide "):tip="Push the guide sideways to change the take-up spool"
	return {"label":best,"distance":limit,"tip":tip}

func capture_origin(label:String):
	var fields=[]
	if label==RIBBON_LEVER or label.begins_with("Ribbon index "):fields=["ribbon"]
	elif label=="Touch regulator":fields=["touch_regulator"]
	elif label.begins_with("Ribbon guide "):fields=["direction"]
	elif label in ["Left shift","Right shift","Shift lock"]:fields=["locked"]
	elif label in tab_keys and label!="TAB":fields=["tabs"]
	at_grab={}
	for field in fields:
		var value=m.writer.data[field]
		at_grab[field]=value.duplicate() if value is Array else value
	if label.begins_with(SLUG) or label=="⇄":
		at_grab["jam"]=jam_snapshot()
		at_grab["margin_released"]=m.writer.data.margin_released

func jam_snapshot()->Dictionary:
	return {"state":m.writer.data.jammed,"keys":jam_keys.duplicate(),"positions":jam_positions.duplicate(),"event_count":m.writer.data.events.size()}

func restore_jam(snapshot:Dictionary):
	if snapshot.event_count!=m.writer.data.events.size():return
	m.writer.data.jammed=snapshot.state
	jam_keys=snapshot["keys"].duplicate()
	jam_positions=snapshot.positions.duplicate()
	cleared=false

func reset_default(label:String):
	var d=m.writer.data
	if label==RIBBON_LEVER or label.begins_with("Ribbon index "):d.ribbon="Black"
	elif label.begins_with("Ribbon guide "):d.direction=1
	elif label=="Touch regulator":d.touch_regulator=1
	elif label in ["Left shift","Right shift","Shift lock"]:
		if label=="Shift lock" or label==m.writer.machine_profile.keyboard.SHIFT_RELEASE_KEY:d.locked=false
		desk.shift_mouse=false
		m.key_latched=false
	elif label=="⇄":
		d.margin_released=false
		if d.jammed:free_jam()
	elif label.begins_with(SLUG) and d.jammed and label.trim_prefix(SLUG) in jam_keys:
		free_jam()

func begin(label:String,pos:Vector2,shifted_input:bool):
	capture_origin(label)
	held=label
	start=pos
	shifted_click=shifted_input
	used_shift=false
	moved=false
	committed=false
	cleared=false
	depth=0.
	elapsed=0.
	travel_velocity.reset(depth)
	if label.begins_with(SLUG):
		var key=label.trim_prefix(SLUG)
		jam_origin=jam_positions[key]
		var tip:Vector3=type_tips[key]
		var pivot=screen(bar_at(key,Vector3.ZERO,jam_origin))
		var extent=screen(bar_at(key,tip,jam_origin))-pivot
		var share=clampf((pos-pivot).dot(extent)/maxf(1.,extent.length_squared()),.35,1.)
		grabbed_bar_point=tip*share
	elif holding_shifter():
		shift_was_locked=m.writer.data.locked
		m.clicked_shift=shift_side()
	elif held=="⇄":
		desk.press_margin_release()
		m.tap_margin_key()
	elif held.begins_with("Ribbon index ") or held.begins_with("Ribbon guide "):
		m.operated.emit(held,false)
	elif held=="Touch regulator" or held==RIBBON_LEVER:
		pass
	else:
		if return_key!="" and return_key!=label:
			m.groups[cap_groups[return_key]].position.y=0.
			if returning_direct and m.writer.meta.bars.has(return_key):set_bar(return_key,0.)
		return_key=""

func is_key()->bool:
	return held!="" and not holding_shifter() and held!="⇄" and held!="Touch regulator" and held!=RIBBON_LEVER and not held.begins_with("Ribbon ") and not held.begins_with(SLUG)

func set_shift_depth(amount:float):
	depth=clampf(amount,0.,1.)
	sample_depth()
	if committed or depth<STRIKE_DEPTH:return
	committed=true
	if (held=="Shift lock" and not m.writer.data.locked) or (held==m.writer.machine_profile.keyboard.SHIFT_RELEASE_KEY and shift_was_locked and m.writer.data.locked):
		pointer_strength=measured_strength() if moved else -1.
		m.operated.emit(held,false)
		pointer_strength=-1.

func available_key_travel(physical:String="")->float:
	if physical=="":physical=held
	if not m.writer.meta.bars.has(physical):return 1.
	var w=m.writer
	if w.data.center_locked or w.carriage_held() or w.data.jammed:return .22
	if w.data.col>w.rail_right() or (w.data.col>w.data.right and not w.margin_bypassed()):return .22
	return 1.

func bind_print_hid(hid:int,key:String):
	if not desk.wooting.connected or not m.writer.meta.bars.has(key):return
	# OS text input supplies the authoritative face for the active keyboard
	# layout, including dead keys and shifted punctuation.
	print_bindings[hid]={"key":key,"seen":desk.wooting.print_positions.has(hid),"expires":Time.get_ticks_msec()+150}

func preview_print_key(hid:int)->String:
	var key=desk.wooting.key_for_hid(hid)
	if key==KEY_NONE:return ""
	if m.writer.data.physical:return desk.physical_pair(key)
	var label=key if DisplayServer.get_name()=="headless" else DisplayServer.keyboard_get_label_from_physical(key)
	if label==KEY_NONE:label=key
	var glyph=""
	if label>=KEY_KP_0 and label<=KEY_KP_9:glyph=str(label-KEY_KP_0)
	elif label>=32 and label<=0x10ffff:glyph=char(label).to_lower()
	if glyph=="":return ""
	var face=m.writer.mappings.get(glyph,[])
	return face[0] if not face.is_empty() else ""

func apply_analog_pretravel(depths:Dictionary)->float:
	var w=desk.wooting
	var active={}
	var previews={}
	var peak_bar=0.
	var reading=w.connected and not (desk.settings.visible or desk.file_dialog.visible or desk.prompt.visible)
	var shortcut=Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META)
	for hid in print_bindings.keys():
		if not w.print_positions.has(hid) and (print_bindings[hid].seen or Time.get_ticks_msec()>print_bindings[hid].expires):
			print_bindings.erase(hid)
	if reading:
		for hid in w.print_positions:
			var bound=print_bindings.has(hid)
			if shortcut and not bound:continue
			var key:String=print_bindings[hid].key if bound else preview_print_key(hid)
			if not m.writer.meta.bars.has(key) or key==drive_key() or key==m.action_grabs.key or key in jam_keys:continue
			var amount=minf(w.print_positions[hid],available_key_travel(key))
			active[key]=maxf(active.get(key,0.),amount)
			if bound:print_bindings[hid].seen=true
			# Until the digital stroke trips the mechanism, keep the slug
			# below contact. Then let the normal hammer motion rebound.
			else:previews[key]=maxf(previews.get(key,0.),minf(amount,.82))
	for key in live_print_keys:
		if active.has(key) or key==drive_key() or key==m.action_grabs.key or key in jam_keys:continue
		var rest:float=depths.get(key,0.)
		set_bar(key,rest)
	for key in active:
		var bar=maxf(depths.get(key,0.),previews.get(key,0.))
		set_bar(key,bar)
		# The Blender-derived key-action track moves the cap about its
		# actual pivot together with the sublever and draw link.
		depths[key]=maxf(depths.get(key,0.),active[key])
		peak_bar=maxf(peak_bar,bar)
	live_print_keys=active
	return peak_bar

func sample_depth():
	travel_velocity.record(depth)

func measured_strength()->float:
	return clampf(inverse_lerp(.7,10.,travel_velocity.speed()),0.,1.)

func drive_key()->String:
	if held.begins_with(SLUG):return held.trim_prefix(SLUG) if not cleared else ""
	if is_key() and (moved or not committed):return held
	return return_key if returning_direct else ""

func drive_depth()->float:
	if held.begins_with(SLUG):return 0. if cleared else float(jam_positions.get(held.trim_prefix(SLUG),0.))
	if is_key() and (moved or not committed):return depth
	return return_depth if returning_direct else 0.

func bar_depth()->float:return drive_depth()

func tab_depth(key:String)->float:
	if held==key and key in tab_keys:return depth
	return desk.wooting.service_depth(43) if key=="TAB" else -1.

func update_service_links():
	for key in service_tracks:
		var amount=0.
		for motion in m.motions:
			if motion.e.key!=key:continue
			var f=clampf(float(motion.t)/motion.duration,0.,1.)
			var a=sin(clampf(f/.46,0.,1.)*PI*.5) if f<.46 else pow(maxf(0.,1.-(f-.46)/.54),1.65)
			amount=maxf(amount,a)
		if held==key:
			amount=depth
			live_service.erase(key)
		elif return_key==key:
			amount=return_depth
			live_service.erase(key)
		else:
			var live=desk.wooting.service_depth(44 if key=="Space" else 42)
			if live>=0.:
				amount=live
				live_service[key]=true
			if live_service.has(key):
				m.groups[cap_groups[key]].position.y=-.041*amount
				if live<0.:live_service.erase(key)
		var previous:float=service_prevs[key]
		if is_equal_approx(amount,previous):continue
		service_recovery[key]=amount<previous
		service_prevs[key]=amount
		var span=amount*12.
		var i=mini(11,floori(span))
		var offset=13 if service_recovery[key] else 0
		for part in service_tracks[key]:
			var samples:Array=service_tracks[key][part]
			m.groups[part].transform=samples[offset+i].interpolate_with(samples[offset+i+1],span-i)

func commit():
	if committed:return
	committed=true
	pointer_strength=measured_strength() if moved else -1.
	m.operated.emit(held,shifted_click)
	pointer_strength=-1.

func nearest_detent(pos:Vector2,points:Array)->int:
	var best=0
	for i in range(1,points.size()):
		if pos.distance_squared_to(points[i])<pos.distance_squared_to(points[best]):best=i
	return best

func set_detent(pos:Vector2):
	if held=="Touch regulator":
		var points=[]
		for p in m.writer.meta.touch_rig.tips:points.append(screen(m.vec(p)))
		var i=nearest_detent(pos,points)
		if i!=m.writer.data.touch_regulator:desk.set_touch_position(i)
	elif held==RIBBON_LEVER or held.begins_with("Ribbon index "):
		var points=[]
		for swatch in SWATCHES:points.append(screen(point("Ribbon index "+swatch)))
		var i=nearest_detent(pos,points)
		if m.writer.data.ribbon!=MODES[i]:m.operated.emit("Ribbon index "+SWATCHES[i],false)
	elif held.begins_with("Ribbon guide "):
		var right=screen(Vector3.RIGHT*.044)-screen(Vector3.ZERO)
		var distance=(pos-start).dot(right.normalized())
		if absf(distance)<maxf(4.,right.length()*.35):return
		# The native guide moves in +X when left take-up engages.
		var direction=-1 if distance>0 else 1
		if m.writer.data.direction!=direction:desk.set_ribbon_direction(direction)

func drag(pos:Vector2):
	if held=="":return
	if start.distance_to(pos)>DEAD_ZONE:moved=true
	if not moved:return
	if held.begins_with(SLUG):
		drag_bar(pos)
	elif holding_shifter():
		var rest=m.vec(m.keys[held])
		var frames=m.shared_shift_tracks[cap_groups[held]]
		var axis=screen(frames[1]*rest)-screen(rest)
		if axis.length()<3.:axis=Vector2.DOWN
		set_shift_depth((pos-start).dot(axis.normalized())/maxf(30.,axis.length()))
	elif is_key():
		var axis=screen(point(held)+Vector3.DOWN*.065)-screen(point(held))
		var span=maxf(30.,axis.length()*2.4)
		depth=clampf((pos-start).dot(axis.normalized())/span,0.,available_key_travel())
		sample_depth()
		if depth<=.04:committed=false
		elif depth>=(space_trip if held=="Space" else STRIKE_DEPTH):commit()
	elif not shifted() and held!="⇄":
		set_detent(pos)

func finish(cancelled:bool):
	if held=="":return
	if holding_shifter():
		if not cancelled and not moved and not committed and not used_shift:
			set_shift_depth(1.)
			if shifted() and not shift_was_locked and elapsed<DWELL:m.operated.emit(held,shifted_click)
	elif held=="⇄":
		m.writer.set_margin_held(desk.active_margin_key!=KEY_NONE)
		desk.changed()
	elif held=="Touch regulator" and not moved and not cancelled:
		m.operated.emit(held,shifted_click)
	elif held==RIBBON_LEVER and not moved and not cancelled:
		var detent=MODES.find(m.writer.data.ribbon)
		var next=posmod(detent+(-1 if shifted_click else 1),4)
		m.operated.emit("Ribbon index "+SWATCHES[next],false)
	elif is_key():
		if not cancelled and not moved and not committed:commit()
		if cap_groups.has(held) and held not in tab_keys and (moved or not committed):
			return_key=held
			return_depth=depth
			returning_direct=moved
		if cancelled and m.writer.meta.bars.has(held) and not committed:
			set_bar(held,0.)
	if cancelled:
		for field in at_grab:
			if field=="jam":restore_jam(at_grab.jam)
			else:m.writer.data[field]=at_grab[field]
		desk.changed()
	at_grab.clear()
	held=""
	depth=0.
	elapsed=0.

func bar_at(key:String,local:Vector3,amount:float)->Vector3:
	var info:Dictionary=m.writer.meta.bars[key]
	var pivot:Node3D=m.groups["bar:"+key]
	return pivot.position+Quaternion(m.vec(info.axis).normalized(),float(info.angle)*amount)*local

func set_bar(key:String,amount:float):
	var info:Dictionary=m.writer.meta.bars[key]
	m.groups["bar:"+key].quaternion=Quaternion(m.vec(info.axis).normalized(),float(info.angle)*amount)

func refresh_jam():
	if not m.writer.data.jammed:return
	var events:Array=m.writer.data.events
	if events.is_empty():return
	var last:Dictionary=events.back()
	if not last.get("jam",false) or not type_tips.has(last.key):return
	if not jam_keys.is_empty() and jam_keys[0]==last.key:return
	jam_keys=[last.key]
	jam_positions={last.key:.71}
	for i in range(events.size()-2,-1,-1):
		var prev:String=events[i].key
		if prev!=last.key and type_tips.has(prev):
			jam_keys.append(prev)
			jam_positions[prev]=.77
			break

func drag_bar(pos:Vector2):
	if cleared or not m.writer.data.jammed:return
	var key=held.trim_prefix(SLUG)
	if not jam_positions.has(key):return
	# Follow the actual crank arc in the camera plane, preserving the part
	# of the stem the finger grabbed at pointer-down.
	var target=screen(bar_at(key,grabbed_bar_point,jam_origin))+(pos-start)
	var best=jam_origin
	var best_distance=INF
	for i in range(49):
		var candidate=jam_origin*i/48.
		var d=target.distance_squared_to(screen(bar_at(key,grabbed_bar_point,candidate)))
		if d<best_distance:best_distance=d;best=candidate
	jam_positions[key]=best
	set_bar(key,best)
	if best<=.23:
		free_jam()

func free_jam():
	m.writer.data.jammed=false
	if m.writer.message.begins_with("Two bars caught") or m.writer.message.begins_with("Typebars jammed"):
		m.writer.message=""
	if not desk.paste_text.is_empty():desk.paused=false
	cleared=true
	desk.changed()
	desk.notice("Typebars freed")

func update(dt:float):
	elapsed+=dt
	if holding_shifter() and not moved:set_shift_depth(elapsed/DWELL)
	if is_key():
		# A stationary finger takes up the key's free play. A short click
		# prints on release; a drag follows its measured travel to contact.
		if not moved:
			if m.writer.meta.bars.has(held):
				depth=minf(.07,elapsed*.9)
				sample_depth()
			else:
				depth=clampf(elapsed/DWELL,0.,1.)
				if elapsed>=DWELL:commit()
		else:
			sample_depth()
		if cap_groups.has(held) and held not in tab_keys:
			m.groups[cap_groups[held]].position.y=-.041*depth
		if m.writer.meta.bars.has(held) and (moved or not committed) and not m.writer.data.jammed:
			set_bar(held,depth)
		if committed and held in tab_keys:m.tab_rig.remaining[held]=maxf(m.tab_rig.remaining[held],.08)
	if return_key!="":
		return_depth=move_toward(return_depth,0.,dt*18.)
		var group:Node3D=m.groups[cap_groups[return_key]]
		group.position.y=-.041*return_depth
		if returning_direct and m.writer.meta.bars.has(return_key) and not m.writer.data.jammed:
			set_bar(return_key,return_depth)
		if is_zero_approx(return_depth):return_key=""
	if m.writer.data.jammed:
		refresh_jam()
		for key in jam_keys:
			var q=float(jam_positions[key])
			if held!=SLUG+key and not (m.action_grabs.held!="" and m.action_grabs.key==key):
				q=move_toward(q,.71 if key==jam_keys[0] else .77,dt*3.)
				jam_positions[key]=q
			set_bar(key,q)
	elif not jam_keys.is_empty():
		for key in jam_keys.duplicate():
			var q=move_toward(float(jam_positions[key]),0.,dt*6.)
			set_bar(key,q)
			jam_positions[key]=q
			if is_zero_approx(q):jam_keys.erase(key)
	update_service_links()
