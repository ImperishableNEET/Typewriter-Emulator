extends SceneTree
## Run against the packaged app with APPDATA redirected to a fresh test directory.
var failures := PackedStringArray()

func _initialize():
	call_deferred("run")

func check(condition:bool, label:String):
	if not condition:
		failures.append(label)
		push_error(label)

func scene_ready():
	for frame in 60:
		await process_frame
		if current_scene != null: return

func send_key(code:Key, shifted:=false):
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.shift_pressed = shifted
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func run():
	if OS.get_environment("HILDA_QA") != "isolated":
		push_error("Run with an isolated profile")
		quit(2)
		return
	change_scene_to_file("res://Desk.tscn")
	await scene_ready()
	var godiva = current_scene
	godiva.writer.action("q",1000)
	check(godiva.finish_page(),"Godiva sheet stacked")
	godiva.load_next_sheet()
	godiva.writer.action("z",1400)
	godiva.switch_machine("hilda")
	await scene_ready()
	var hilda = current_scene
	check(hilda != null and hilda.name=="HildaDesk","Hilda scene opened")
	if not failures.is_empty(): quit(1); return
	check(hilda.writer.data.finished_pages.size()==1,"Godiva page visible on Hilda")
	check(hilda.machine.pivots.size()>=4,"Imported actuators available")
	var blank = hilda.writer.raster.get_data()
	var carriage = hilda.machine.pivots[&"HildaCarriage"]
	var original:Vector3 = carriage.position
	send_key(KEY_H)
	check(hilda.writer.data.events.size()==1 and hilda.writer.data.events[0].glyph=="h","Physical h key resolved")
	check(blank==hilda.writer.raster.get_data(),"Ink waits for contact")
	hilda.machine._process(.026)
	check(hilda.machine.pivots[&"HildaHBar"].transform!=hilda.machine.rest[&"HildaHBar"],"Typebar left its rest")
	hilda.machine._process(.25)
	check(blank!=hilda.writer.raster.get_data(),"Contact printed Hilda’s h")
	check(carriage.position.x<original.x,"Escapement advanced one column")
	send_key(KEY_H,true)
	hilda.machine.flush()
	check(hilda.writer.data.events.size()==2 and hilda.writer.data.events[1].glyph=="H","Shift+H printed the capital")
	hilda.stack_sheet()
	check(hilda.writer.data.finished_pages.size()==2,"Hilda page stacked beside Godiva’s")
	var archived = hilda.writer.finished_image(1).get_data()
	hilda.stack_sheet()
	var key_mesh:MeshInstance3D = hilda.machine.key_meshes[0]
	var cap_center:Vector3 = key_mesh.global_transform * key_mesh.get_aabb().get_center()
	var pixel:Vector2 = hilda.machine.camera.unproject_position(cap_center)
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.shift_pressed=true
	click.position=pixel * hilda.machine.size / Vector2(hilda.machine.view.size)
	hilda.machine._gui_input(click)
	check(hilda.writer.data.events.size()==1,"Click hit the imported H keycap")
	hilda.switch_machine("godiva")
	await scene_ready()
	godiva=current_scene
	check(godiva.writer.data.col==1 and godiva.writer.data.events[0].glyph=="z","Godiva mounted draft restored")
	check(godiva.writer.data.finished_pages.size()==2 and godiva.writer.finished_image(1).get_data()==archived,"Original Hilda pixels survived machine switch")
	godiva.switch_machine("hilda")
	await scene_ready()
	hilda=current_scene
	check(hilda.writer.data.events.size()==1 and hilda.writer.data.events[0].glyph=="H","In-flight click persisted to Hilda’s private draft")
	check(hilda.writer.data.finished_pages.size()==2,"Switching again keeps one of each finished sheet")
	hilda.stack_sheet()
	hilda.stack_sheet()
	var sentence := "The quick brown fox jumps over the lazy dog."
	var strike_index := 0
	var bar_ids := {}
	var key_ids := {}
	var link_ids := {}
	for i in sentence.length():
		var glyph := sentence[i]
		var code := glyph.to_upper().unicode_at(0)
		send_key(code, glyph != glyph.to_lower())
		if glyph == " ":
			hilda.machine._process(.25)
			continue
		var key := glyph.to_upper()
		var stem := "Hilda" + ("Period" if glyph == "." else key)
		var arm:Node3D = hilda.machine.model.find_child(stem+"Bar",true,false)
		var lever:Node3D = hilda.machine.model.find_child(stem+"Key",true,false)
		var link:Node3D = hilda.machine.model.find_child(stem+"Link",true,false)
		check(arm!=null and lever!=null and link!=null,"Physical linkage for "+glyph)
		if arm==null or lever==null or link==null: quit(1); return
		var idle := arm.transform
		var idle_lever := lever.transform
		var idle_link := link.transform
		hilda.machine._process(.026)
		check(arm.transform!=idle and lever.transform!=idle_lever and link.transform!=idle_link,"Coordinated lever, link and typebar movement for "+glyph)
		bar_ids[arm.get_instance_id()]=true
		key_ids[lever.get_instance_id()]=true
		link_ids[link.get_instance_id()]=true
		hilda.machine._process(.25)
		check(arm.transform.is_equal_approx(idle),"Typebar returned after "+glyph)
		var event:Dictionary = hilda.writer.data.events[strike_index]
		check(event.glyph==glyph and event.col==i and event.key==key,"Actual impression and position for "+glyph)
		strike_index += 1
	check(bar_ids.size()==27 and key_ids.size()==27 and link_ids.size()==27,"Twenty-seven independent mechanical actions")
	check(hilda.writer.data.col==sentence.length() and hilda.writer.pending_ink.is_empty(),"Final period advanced the carriage")
	var sentence_image = hilda.writer.raster.get_data()
	var background = hilda.writer.raster.get_pixel(2,2)
	for i in sentence.length():
		var marked := false
		var x0:int = hilda.writer.MARGIN+i*hilda.writer.PITCH
		for y in range(hilda.writer.BASE-16,hilda.writer.BASE+7):
			for x in range(x0+1,x0+hilda.writer.PITCH-1):
				if hilda.writer.raster.get_pixel(x,y).r < background.r-0.035:
					marked = true
					break
			if marked: break
		check(marked==(sentence[i]!=" "),"Ink coverage in pangram column "+str(i+1))
	hilda.switch_machine("godiva")
	await scene_ready()
	current_scene.switch_machine("hilda")
	await scene_ready()
	check(current_scene.writer.raster.get_data()==sentence_image,"Mounted pangram pixels survived round trip")
	hilda=current_scene
	send_key(KEY_ENTER)
	for code in range(KEY_A,KEY_Z+1): send_key(code,true)
	hilda.machine.flush()
	for i in 26:
		var upper:Dictionary=hilda.writer.data.events[strike_index+i]
		check(upper.glyph == String.chr(KEY_A+i) and upper.shift,"Shifted face for "+String.chr(KEY_A+i))
	check(hilda.strike_audio.strikes.size()==6,"Six imported owner recordings")
	if failures.is_empty(): print("HILDA_FIRST_ACTION_OK")
	quit(0 if failures.is_empty() else 1)
