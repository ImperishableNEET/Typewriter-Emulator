extends SceneTree
## Run with an isolated APPDATA and HILDA_QA=isolated.
var failures := PackedStringArray()

func _initialize():
	call_deferred("run")

func check(condition:bool, label:String):
	if not condition:
		failures.append(label)
		push_error(label)

func press(code:Key, alt:=false):
	var event := InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.alt_pressed=alt
	event.pressed=true
	root.push_input(event)
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)

func run():
	if OS.get_environment("HILDA_QA")!="isolated":
		quit(2)
		return
	change_scene_to_file("res://machines/hilda/HildaDesk.tscn")
	await process_frame
	await process_frame
	var desk=current_scene
	var writer=desk.writer
	var rig=desk.machine
	writer.reset()
	desk.browse(-1)
	for id in [&"HildaReturnLever",&"HildaLineSpacingSelector",&"HildaPlatenRoll"]:
		check(rig.pivots.has(id),"Imported carriage pivot "+str(id))
	if not failures.is_empty(): quit(1); return
	writer.data.left=2
	writer.move_col(18)
	desk.spacing_control.item_selected.emit(1)
	press(KEY_A)
	press(KEY_ENTER)
	press(KEY_B)
	check(writer.data.events[0].col==18 and writer.data.events[1].col==2,"Return to set left margin between queued strikes")
	check(writer.data.events[0].half==0 and writer.data.events[1].half==3,"One-and-a-half line registration")
	rig._process(.16)
	rig._process(.065)
	check(not rig.pivots[&"HildaReturnLever"].transform.is_equal_approx(rig.rest[&"HildaReturnLever"]),"Physical return lever swings")
	rig._process(.9)
	check(rig.pivots[&"HildaReturnLever"].transform.is_equal_approx(rig.rest[&"HildaReturnLever"]),"Return spring restores lever")
	check(writer.pending_ink.is_empty() and writer.data.events.size()==2,"Both queued contacts completed")
	rig.carriage_control_requested.emit("spacing",2.0)
	rig.carriage_control_requested.emit("return",1.0)
	check(writer.data.half==7 and writer.data.col==2,"Double-space return")
	var column:int=writer.data.col
	press(KEY_DOWN,true)
	press(KEY_UP,true)
	check(writer.data.half==7 and writer.data.col==column,"Bidirectional platen rotation preserves the column")
	rig.carriage_control_requested.emit("spacing",3.0)
	rig.carriage_control_requested.emit("platen",0.375)
	check(is_equal_approx(writer.data.half,7.375),"Free platen accepts fractional travel")
	check(is_equal_approx(writer.data.half,writer.data.platen_half),"Paper follows knob rotation")
	rig.flush()
	var expected:Transform3D=rig.pivots[&"HildaPlatenRoll"].transform
	rig.carriage_control_requested.emit("platen",-0.375)
	rig.flush()
	check(not rig.pivots[&"HildaPlatenRoll"].transform.is_equal_approx(expected),"Both knobs' common shaft rotates")
	rig.carriage_control_requested.emit("spacing",0.0)
	rig.carriage_control_requested.emit("return",1.0)
	check(writer.data.half==9 and writer.data.col==2,"Single-spacing detent restored")
	rig.flush()
	desk.spacing_control.item_selected.emit(1)
	desk.save_draft()
	var loaded=load("res://Writer.gd").new(writer.meta,desk.machine_profile)
	check(loaded.load_file(desk.machine_profile.autosave_path) and loaded.data.spacing==1.5 and loaded.data.half==9,"Draft preserves selector and paper registration")
	rig.set_carriage_view(true)
	var knob:Node3D=rig.left_knob
	var hit:Vector3=knob.global_transform*knob.get_aabb().get_center()
	var pixel:Vector2=rig.camera.unproject_position(hit)*rig.size/Vector2(rig.view.size)
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	click.ctrl_pressed=true
	click.position=pixel
	rig._gui_input(click)
	check(rig.registration_pulled and knob.position.x<rig.knob_home.x,"Ctrl-click pulls out actual left knob")
	var fixed_basis:Basis=rig.ratchet.global_basis
	var delta:Vector2=rig.grab_axis*rig.grab_travel_px*2.375
	if delta.length()<5: delta*=2.0
	var drag:=InputEventMouseMotion.new()
	drag.position=pixel+delta
	drag.button_mask=MOUSE_BUTTON_MASK_LEFT
	rig._gui_input(drag)
	var registered:float=writer.data.half
	check(registered>9 and not is_equal_approx(registered,roundf(registered)),"Drag moves paper by a fractional interval")
	check(writer.data.ratchet_half==9 and rig.ratchet.global_basis.is_equal_approx(fixed_basis),"Disengaged line-space wheel stays fixed in model and state")
	click.pressed=false
	rig._gui_input(click)
	check(not rig.registration_pulled and knob.position.is_equal_approx(rig.knob_home),"Release seats the knob without disturbing register")
	press(KEY_C)
	press(KEY_ENTER)
	press(KEY_D)
	rig.flush()
	check(is_equal_approx(writer.data.events[-2].half,registered) and is_equal_approx(writer.data.events[-1].half,registered+3),"New baseline survives printing and 1½-line return")
	var origin:float=writer.data.half
	var ratchet_index:float=writer.data.ratchet_half
	rig._begin_handle("Left knob",pixel,hit,true)
	rig._drag_handle(pixel+delta)
	rig._end_handle(true)
	check(is_equal_approx(writer.data.half,origin) and is_equal_approx(writer.data.ratchet_half,ratchet_index),"Cancelled adjustment restores paper and ratchet")
	desk.save_draft()
	check(loaded.load_file(desk.machine_profile.autosave_path) and is_equal_approx(loaded.data.platen_half-loaded.data.ratchet_half,registered-9),"New registration survives save and reopen")
	if failures.is_empty(): print("HILDA_CARRIAGE_OK")
	quit(0 if failures.is_empty() else 1)
