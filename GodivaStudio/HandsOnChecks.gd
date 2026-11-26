extends RefCounted

static func mouse(m,pos:Vector2,down:bool):
	var e=InputEventMouseButton.new()
	e.position=pos;e.pressed=down;e.button_index=MOUSE_BUTTON_LEFT
	m._gui_input(e)

static func move(m,pos:Vector2):
	var e=InputEventMouseMotion.new()
	e.position=pos;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	m._gui_input(e)

static func run(desk):
	var m=desk.machine
	var w=desk.writer
	w.reset()
	m.set_cut(true)
	desk.sync()
	m._process(.1)
	# Both keys work a single basket. A handoff must keep the same recorded
	# stroke open until the second hand lets the basket return.
	m.shift_inputs=Vector2(1.,0.)
	m.update_shift_linkage(.10,0.)
	var take:int=desk.shift_take
	desk.check(take>=0 and desk.mechanism_audio.bank.shift_press.size()>=2 and desk.mechanism_audio.bank.shift_release.size()==desk.mechanism_audio.bank.shift_press.size(),"Shift has paired recorded press and release variations")
	m.shift_inputs=Vector2(0.,1.)
	m.update_shift_linkage(.10,0.)
	desk.check(desk.shift_take==take and m.shift_bottom_contact,"the second Shift holds the original basket stroke")
	m.shift_inputs=Vector2.ZERO
	m.update_shift_linkage(.10,0.)
	desk.check(desk.shift_take==-1 and not m.shift_bottom_contact and m.shift_sound_source=="Right shift","return contact fires at the releasing hand")
	for label in ["Left shift","Right shift","Shift lock"]:
		var g=m.key_grabs
		var rest_point=m.vec(m.keys[label])
		var endpoints=m.shared_shift_tracks[g.cap_groups[label]]
		var origin=g.screen(rest_point)
		var axis=g.screen(endpoints[1]*rest_point)-origin
		if axis.length()<3.:axis=Vector2.DOWN
		var travel=axis.normalized()*maxf(30.,axis.length())
		mouse(m,origin,true)
		move(m,origin+travel*.5)
		m._process(.1)
		desk.check(g.held==label and absf(m.shared_shift_depth-.5)<.02 and absf(m.shift_offset-.033)<.002,"drag "+label+" moves the coupled keys and basket halfway")
		move(m,origin+travel)
		m._process(.1)
		desk.check(w.data.locked==(label=="Shift lock"),"full travel engages only the lock key")
		mouse(m,origin+travel,false)
		m._process(.1)
		desk.check(is_equal_approx(m.shared_shift_depth,float(w.data.locked)),"release "+label+" follows latch")
	var grabs=m.key_grabs
	for label in ["Right shift","Left shift"]:
		var p=grabs.screen(grabs.point(label))
		mouse(m,p,true)
		m._process(.2)
		desk.check(w.data.locked==(label=="Right shift"),"holding "+label+" operates the correct latch linkage")
		var cancel=InputEventMouseButton.new()
		cancel.position=p
		cancel.button_index=MOUSE_BUTTON_RIGHT
		cancel.pressed=true
		m._gui_input(cancel)
		desk.check(w.data.locked and grabs.held=="","cancel restores the latched position")
		cancel.pressed=false
		m._gui_input(cancel)
	w.data.locked=false
	m._process(.1)
	var snd=desk.writer.data.volume
	desk.writer.data.volume=0.
	var pos=m.camera.unproject_position(m.key_grabs.point("L"))
	var step=m.camera.unproject_position(Vector3.DOWN*.065)-m.camera.unproject_position(Vector3.ZERO)
	var span=step.normalized()*maxf(30.,step.length()*2.4)
	var group=""
	for name in m.key_action.tracks["L"]:
		if "sublever" in name:group=name
	var neighbour=""
	for name in m.key_action.tracks["K"]:
		if "sublever" in name:neighbour=name
	var rest:Transform3D=m.groups[group].transform
	var other:Transform3D=m.groups[neighbour].transform
	mouse(m,pos,true)
	move(m,pos+span*.55)
	m._process(.025)
	desk.check(m.key_grabs.held=="L" and m.key_grabs.drive_depth()>.45,"pointer captures the L cap and depresses it progressively")
	desk.check(not m.groups[group].transform.is_equal_approx(rest) and m.groups[neighbour].transform.is_equal_approx(other),"only the selected linkage moves at partial travel")
	desk.check(w.data.events.is_empty(),"an incomplete hand stroke makes no impression")
	move(m,pos+span*.17)
	m._process(.025)
	mouse(m,pos,false)
	m._process(.25)
	desk.check(w.data.events.is_empty() and m.groups[group].transform.is_equal_approx(rest),"partial stroke returns without printing")
	mouse(m,pos,true)
	move(m,pos+span)
	m._process(.016)
	move(m,pos+span*.97)
	desk.check(w.data.events.size()==1 and w.data.events.back().has("pointer_strength"),"one hand-driven impression at contact")
	mouse(m,pos,false)
	m._process(.25)
	var before=int(w.data.half)
	w.move_col(8)
	desk.sync();m._process(.2)
	var spoon=m.camera.unproject_position(m.paper_grabs.target("Carriage return"))
	mouse(m,spoon,true)
	desk.check(m.grab_owner==m.paper_grabs,"the return spoon is pickable")
	mouse(m,spoon,false)
	desk.check(w.data.col==w.data.left and w.data.half==before+2,"tapping the spoon returns and indexes the paper")
	m.set_cut(false)
	w.reset();w.data.volume=snd;desk.sync()
