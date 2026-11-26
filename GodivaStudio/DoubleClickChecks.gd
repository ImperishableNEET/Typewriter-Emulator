extends RefCounted
const Pointer=preload("res://HandsOnChecks.gd")

static func button(pos:Vector2,down:bool,double:=false)->InputEventMouseButton:
	var e=InputEventMouseButton.new()
	e.position=pos
	e.pressed=down
	e.double_click=double
	e.button_index=MOUSE_BUTTON_LEFT
	return e

static func click(m,pos:Vector2,double:=false):
	m._gui_input(button(pos,true,double))
	m._gui_input(button(pos,false))

static func run(desk):
	var m=desk.machine
	var w=desk.writer
	w.reset()
	desk.sync()
	m.set_cut(false)
	m._process(.3)
	var l:Vector2=m.camera.unproject_position(m.key_grabs.point("L"))
	click(m,l)
	click(m,l,true)
	desk.check(w.data.events.size()==2 and w.data.events[0].input=="l" and w.data.events[1].input=="l","double-clicking a printable key types both impressions")
	w.data.bail_left=.40
	m._process(.2)
	var roller:Vector2=m.camera.unproject_position(m.groups.roller_left.position)
	click(m,roller)
	click(m,roller,true)
	desk.check(is_equal_approx(w.data.bail_left,.22),"double-click restores just the selected roller")
	w.data.spacing=2
	var selector:Vector2=m.camera.unproject_position(m.paper_grabs.target("Line spacing selector"))
	m._gui_input(button(selector,true))
	# Captured releases reach global input first, including outside the viewport.
	m._input(button(m.get_global_transform_with_canvas()*selector,false))
	desk.check(w.data.spacing==3,"first selector click operates immediately")
	click(m,selector,true)
	desk.check(w.data.spacing==1 and not w.data.free_platen,"second selector click restores single spacing")
	w.data.bail_left=.38
	m._process(.2)
	roller=m.camera.unproject_position(m.groups.roller_left.position)
	click(m,roller)
	click(m,selector,true)
	desk.check(is_equal_approx(w.data.bail_left,.38) and w.data.spacing==2,"a double flag on a different part acts as an ordinary click")
	m._gui_input(button(roller,true))
	Pointer.move(m,roller+Vector2(24,0))
	m._gui_input(button(roller+Vector2(24,0),false))
	desk.check(not m.double_click_reset.released and not is_equal_approx(w.data.bail_left,.38),"dragging moves a roller and disqualifies a double reset")
	w.move_col(10)
	m.sync()
	m._process(.5)
	var spoon:Vector2=m.camera.unproject_position(m.paper_grabs.target("Carriage return"))
	var line:float=w.data.half
	click(m,spoon)
	m._process(.25)
	click(m,spoon,true)
	desk.check(int(w.data.col)==10 and w.data.half==line,"return lever double-click retracts first-click paper and carriage travel")
	var healthy={"owner":m.action_grabs,"label":"Draw link L"}
	desk.check(not m.double_click_reset.eligible(m,healthy),"healthy linkage is exempt from double reset")
	w.data.jammed=true
	m.key_grabs.jam_keys=["L"]
	desk.check(m.double_click_reset.eligible(m,healthy) and not m.double_click_reset.eligible(m,{"owner":m.action_grabs,"label":"Typebar K"}),"only the caught action accepts jam reset")
	m.key_grabs.jam_keys.clear()
	m.double_click_reset.forget()
	w.reset()
	desk.sync()
