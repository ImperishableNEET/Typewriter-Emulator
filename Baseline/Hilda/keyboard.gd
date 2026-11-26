extends SceneTree
## Independent transcription of the owner's full keyboard photograph.
const ROWS := [
	["Number", "=234567890-¾", '=234567890-¾', "+\"#$%_&'()*!"],
	["Upper", "QWERTYUIOP½", "qwertyuiop½", "QWERTYUIOP¼"],
	["Home", "ASDFGHJKL;¢", "asdfghjkl;¢", "ASDFGHJKL:@"],
	["Lower", "ZXCVBNM,./", "zxcvbnm,./", "ZXCVBNM,.?"],
]

var failures := PackedStringArray()

func _initialize():
	call_deferred("run")

func check(ok:bool, message:String):
	if not ok:
		failures.append(message)
		push_error(message)

func text(desk, value:String):
	for glyph in value:
		desk.type_character(glyph)
		desk.machine.flush()

func click_cap(desk, key:String, upper:bool):
	var cap = desk.machine.cap_for_key(key)
	check(cap != null, "Missing physical cap "+key)
	if cap == null: return
	var center:Vector3 = cap.global_transform * cap.get_aabb().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.shift_pressed = upper
	click.position = desk.machine.camera.unproject_position(center) * desk.machine.size / Vector2(desk.machine.view.size)
	desk.machine._gui_input(click)

func keyboard(code:int, shifted:=false, unicode:=0, shortcut:=false):
	var e := InputEventKey.new()
	e.keycode=code
	e.physical_keycode=code
	e.unicode=unicode
	e.shift_pressed=shifted
	e.ctrl_pressed=shortcut
	e.alt_pressed=shortcut
	e.pressed=true
	root.push_input(e)
	e=e.duplicate()
	e.pressed=false
	root.push_input(e)

func run():
	if OS.get_environment("HILDA_QA")!="isolated":
		quit(2)
		return
	change_scene_to_file("res://machines/hilda/HildaDesk.tscn")
	await process_frame
	await process_frame
	var desk = current_scene
	var writer = desk.writer
	writer.new_stock("Letter")
	writer.data.seed=13639
	var inspected := {}
	var faces := {}
	var count := 0
	for row in ROWS:
		for side in 2:
			writer.data.ribbon="Red"
			text(desk,("%s  %s" % [row[0],"Shift" if side else "Plain"]).rpad(17))
			writer.data.ribbon="Black"
			for i in row[1].length():
				var key:String=row[1][i]
				var glyph:String=row[2+side][i]
				var event_count:int=writer.data.events.size()
				var column:int=writer.data.col
				click_cap(desk,key,side==1)
				if writer.data.events.size()!=event_count+1:
					check(false,"Cap did not generate one event for "+key)
					quit(1)
					return
				var event:Dictionary=writer.data.events.back()
				check(event.key==key and event.glyph==glyph and event.shift==(side==1),"Wrong slug/face/Shift for "+key)
				var ids:Array=desk.machine.actions[key]
				var arm:Node3D=desk.machine.pivots[ids[2]]
				var idle:=arm.transform
				desk.machine._process(.025)
				check(not arm.transform.is_equal_approx(idle),"Bar stayed parked for "+key)
				desk.machine._process(.25)
				check(arm.transform.is_equal_approx(idle),"Bar did not return for "+key)
				check(not writer.pending_ink.has(event.sheet_index),"Missing contact for "+key)
				var y0:int=roundi(writer.BASE+event.half*writer.LEADING*.5)
				var x0:int=writer.MARGIN+column*writer.PITCH
				var darkest:=1.0
				for y in range(y0-20,y0+9):
					for x in range(x0-1,x0+writer.PITCH+1):
						darkest=minf(darkest,writer.raster.get_pixel(x,y).r)
				check(darkest<0.88,"Blank impression for "+key)
				inspected[arm.get_instance_id()]=true
				faces[glyph]=true
				count+=1
				text(desk," ")
			text(desk,"\n")
		text(desk,"\n")
	check(inspected.size()==44 and count==88 and faces.size()==86,"Expected 44 bars, 88 faces tested and 86 distinct glyphs")
	var output:=OS.get_environment("HILDA_PROOF")
	if not output.is_empty() and failures.is_empty():
		var proof:Image=writer.raster.get_region(Rect2i(32,34,610,288))
		proof.resize(proof.get_width()*2,proof.get_height()*2,Image.INTERPOLATE_CUBIC)
		check(proof.save_png(output)==OK,"Could not save the keyboard proof")
	writer.new_stock("Letter")
	writer.data.physical=false
	keyboard(KEY_1,false,49)
	check(writer.data.events.back().glyph=="l" and writer.data.events.back().key=="L","Desktop 1 should operate lowercase l")
	keyboard(KEY_1,true,33)
	check(writer.data.events.back().glyph=="!" and writer.data.events.back().key=="¾","Desktop ! maps to shifted ¾")
	for pair in [[KEY_Q,"¼"],[KEY_H,"½"],[KEY_T,"¾"],[KEY_P,"¢"]]:
		keyboard(pair[0],true,0,true)
		check(writer.data.events.back().glyph==pair[1],"Shortcut for "+str(pair[1]))
	writer.data.physical=true
	for row in ROWS:
		var positions=[KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0,KEY_MINUS,KEY_EQUAL] if row==ROWS[0] else []
		for i in row[1].length():
			var key:String=row[1][i]
			var code:int=positions[i] if positions else {"½":KEY_BRACKETLEFT,";":KEY_SEMICOLON,"¢":KEY_APOSTROPHE,",":KEY_COMMA,".":KEY_PERIOD,"/":KEY_SLASH}.get(key,key.unicode_at(0))
			keyboard(code,true)
			check(writer.data.events.back().glyph==row[3][i] and writer.data.events.back().shift,"Physical position for "+key)
	desk.machine.flush()
	if failures.is_empty():print("HILDA_KEYBOARD_OK 44 bars, 88 impressions, 86 distinct glyphs")
	quit(0 if failures.is_empty() else 1)
