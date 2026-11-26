extends RefCounted

const Pointer = preload("res://HandsOnChecks.gd")

static func screen(m, label:String, depth:float, fraction:float)->Vector2:
	return m.camera.unproject_position(m.action_grabs.position_at(label,depth,fraction))

# Find a visible point whose winner in the full input dispatcher is this part.
static func grab(m, label:String, jam_bar:=false)->bool:
	var target_depth:float=m.action_grabs.current(label)
	var wanted=label
	if jam_bar:
		var key:String=m.action_grabs.paths[label].key
		target_depth=m.key_grabs.jam_positions[key]
		wanted=m.key_grabs.SLUG+key
	for fraction in [1.,.83,.64,.5,.25,0.]:
		var pos=screen(m,label,target_depth,fraction)
		if m.choose_grab(pos).get("label","")==wanted:
			Pointer.mouse(m,pos,true)
			return true
	return false

static func pull(m,goal:float):
	var g=m.action_grabs
	var destination=screen(m,g.held,goal,g.grab_fraction)
	var origin=screen(m,g.held,g.initial,g.grab_fraction)
	Pointer.move(m,g.start+destination-origin)
	m._process(.025)

static func release(m):
	Pointer.mouse(m,Vector2.ZERO,false)
	m._process(.5)

static func stroke(desk,label:String,complete:bool):
	var m=desk.machine
	var w=desk.writer
	var count=w.data.events.size()
	var key:String=m.action_grabs.paths[label].key
	var cap=m.groups[m.key_grabs.cap_groups[key]]
	var rest:Transform3D=cap.transform
	var captured=grab(m,label)
	desk.check(captured,label+" wins pointer picking")
	if not captured:return
	pull(m,.52)
	desk.check(not cap.transform.is_equal_approx(rest) and m.action_grabs.depth>.35 and m.action_grabs.depth<.7,label+" drives the linked key through partial travel")
	desk.check(w.data.events.size()==count,label+" partial stroke leaves the page alone")
	if complete:
		pull(m,1.)
		pull(m,.98)
	release(m)
	desk.check(w.data.events.size()==count+int(complete),label+" produces exactly the intended number of strikes")
	desk.check(cap.transform.is_equal_approx(rest),label+" releases its linked key to rest")

static func guide(desk,cancelled:=false):
	var m=desk.machine
	var w=desk.writer
	var count=w.data.events.size()
	var grabbed=grab(m,m.action_grabs.GUIDE)
	desk.check(grabbed,"type guide bearing wins pointer picking")
	if not grabbed:return
	pull(m,1.)
	m._process(.25)
	desk.check(m.shift_offset>.06,"lifting the guide shifts the segment")
	var e=InputEventKey.new()
	e.physical_keycode=KEY_A;e.keycode=KEY_A;e.unicode=97;e.pressed=true
	desk._input(e)
	e.pressed=false;desk._input(e)
	desk.check(w.data.events.size()==count+1 and w.data.events.back().glyph=="A","keyboard prints uppercase while pointer holds the type guide")
	if cancelled:
		var col=w.data.col
		cancel_drag(desk)
		desk.check(w.data.col==col and w.data.events.size()==count+1 and w.data.events.back().glyph=="A","cancelling guide preserves the independent keyboard impression and carriage step")
	else:release(m)
	m._process(.5)
	desk.check(m.shift_offset<.002 and w.data.events.size()==count+1,"releasing the guide settles without printing")

static func jam(desk,bar:bool,cancelled:=false):
	var m=desk.machine
	var w=desk.writer
	w.reset()
	desk.type_char("a")
	desk.type_char("l")
	# Set the writer's persisted collision result independently of timing randomness.
	w.data.events.back().jam=true
	w.data.jammed=true
	m._process(.5)
	var count=w.data.events.size()
	var col=w.data.col
	var label="Typebar L" if bar else "Draw link L"
	var grabbed=grab(m,label,bar)
	desk.check(grabbed,label+" picks the already jammed mechanism")
	if grabbed:
		if bar:
			var g=m.key_grabs
			var dest=m.camera.unproject_position(g.bar_at("L",g.grabbed_bar_point,.45 if cancelled else 0.))
			var origin=m.camera.unproject_position(g.bar_at("L",g.grabbed_bar_point,g.jam_origin))
			Pointer.move(m,g.start+dest-origin)
		else:pull(m,0.)
		if cancelled:
			desk.check(float(m.key_grabs.jam_positions.L)<.65,"caught bar moved before cancellation")
			cancel_drag(desk)
			desk.check(w.data.jammed and is_equal_approx(m.key_grabs.jam_positions.L,.71),"cancelling a caught bar restores its lodged position")
		else:
			release(m)
			desk.check(not w.data.jammed,label+" frees the lodged bars")
	desk.check(w.data.events.size()==count and w.data.col==col,label+" jam release adds no impression or escapement step")
	w.data.jammed=false
	m._process(.5)

static func right_event(m,down:bool):
	var e=InputEventMouseButton.new()
	e.button_index=MOUSE_BUTTON_RIGHT
	e.pressed=down
	e.button_mask=MOUSE_BUTTON_MASK_RIGHT if down else 0
	e.position=m.get_global_transform_with_canvas()*(m.size*.5)
	m.get_viewport().push_input(e,true)

static func cancel_drag(desk,check_orbit:=false):
	var m=desk.machine
	var starting_yaw=m.yaw
	right_event(m,true)
	desk.check(not m.grab_owner and not m.carriage_dragging,"right press cancels the captured pointer")
	# Physical left-up can arrive while right is still held.
	Pointer.mouse(m,Vector2.ZERO,false)
	if check_orbit:
		var motion=InputEventMouseMotion.new()
		motion.position=m.get_global_transform_with_canvas()*(m.size*.5)
		motion.relative=Vector2(17.,6.)
		motion.button_mask=MOUSE_BUTTON_MASK_RIGHT
		m.get_viewport().push_input(motion,true)
		desk.check(is_equal_approx(m.yaw,starting_yaw),"right mouse motion after cancelling cannot orbit")
		right_event(m,false)
		right_event(m,true)
		m.get_viewport().push_input(motion,true)
		desk.check(not is_equal_approx(m.yaw,starting_yaw),"a new right drag can orbit after right release")
	right_event(m,false)
	m._process(.5)

static func cancel_controls(desk):
	var m=desk.machine
	var w=desk.writer
	w.reset()
	m.set_cut(false)
	w.move_col(w.bank_center_column())
	desk.sync()
	m.travel=m.target_travel
	m._process(.5)
	var axis=m.camera.unproject_position(Vector3.RIGHT)-m.camera.unproject_position(Vector3.ZERO)
	var roller=m.camera.unproject_position(m.groups.roller_left.position)
	var initial_roller=w.data.bail_left
	Pointer.mouse(m,roller,true)
	Pointer.move(m,roller+axis*.28)
	desk.check(w.data.bail_left>initial_roller+.05,"roller moved before cancellation")
	cancel_drag(desk,true)
	desk.check(is_equal_approx(w.data.bail_left,initial_roller),"cancelling the bail roller restores its lateral position")

	m.set_cut(false)
	axis=m.camera.unproject_position(Vector3.RIGHT)-m.camera.unproject_position(Vector3.ZERO)
	var col=w.carriage_column()
	var button=m.camera.unproject_position(m.carriage_rig.point("Carriage release left"))
	Pointer.mouse(m,button,true)
	Pointer.move(m,button-axis*.115)
	desk.check(w.carriage_held() and w.carriage_column()>col+3.,"carriage release moved the unseated carriage before cancellation")
	cancel_drag(desk)
	desk.check(not w.carriage_held() and is_equal_approx(w.carriage_column(),col),"cancelling carriage drag reseats its original column")

	var original_ribbon=w.data.ribbon
	var selector=m.camera.unproject_position(m.key_grabs.point(m.key_grabs.RIBBON_LEVER))
	var red=m.camera.unproject_position(m.key_grabs.point("Ribbon index Red"))
	Pointer.mouse(m,selector,true)
	Pointer.move(m,red)
	desk.check(w.data.ribbon=="Red","ribbon lever selected the red band before cancellation")
	cancel_drag(desk)
	desk.check(w.data.ribbon==original_ribbon,"cancelling ribbon selection restores its original band")

	var touch=w.data.touch_regulator
	var lever=m.camera.unproject_position(m.key_grabs.point("Touch regulator"))
	var tip=m.camera.unproject_position(m.vec(w.meta.touch_rig.tips[3]))
	Pointer.mouse(m,lever,true)
	Pointer.move(m,tip)
	desk.check(w.data.touch_regulator==3,"touch selector moved to another detent before cancellation")
	cancel_drag(desk)
	desk.check(w.data.touch_regulator==touch,"cancelling the touch selector restores its original detent")

	m.set_cut(true)
	var cap=m.groups[m.key_grabs.cap_groups["L"]]
	var rest:Transform3D=cap.transform
	var caught=grab(m,"Typebar L")
	desk.check(caught,"typebar captured for cancellation")
	if caught:
		pull(m,.55)
		desk.check(not cap.transform.is_equal_approx(rest),"linked cap moved before cancellation")
		cancel_drag(desk)
		desk.check(cap.transform.is_equal_approx(rest) and w.data.events.is_empty(),"cancelling a partially pulled bar restores the action without printing")
	guide(desk,true)
	jam(desk,true,true)

static func run(desk):
	var m=desk.machine
	desk.writer.reset()
	m.set_cut(true)
	desk.sync()
	m._process(.5)
	stroke(desk,"Typebar L",false)
	stroke(desk,"Draw link L",true)
	stroke(desk,"Sublever L",false)
	guide(desk)
	jam(desk,true)
	jam(desk,false)
	cancel_controls(desk)
	m.set_cut(false)
	desk.writer.reset()
	desk.sync()
