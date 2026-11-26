extends RefCounted
const Pointer=preload("res://HandsOnChecks.gd")
const Click=preload("res://DoubleClickChecks.gd")

static func run(desk):
	var w=desk.writer
	var m=desk.machine
	var ears=m.bail_grabs
	w.reset()
	desk.sync()
	m.set_cut(false)
	m.yaw=PI+.8
	m.tilt=.30
	m._process(.6)
	var label="Paper support left"
	var other="Paper support right"
	var raised:Vector3=ears.target(other)
	var face:Vector2=m.paper_section(-1.6)
	var nip:Vector2=m.paper_section(.12)
	var anchor:Vector2=ears.screen(ears.target(label))
	Click.click(m,anchor)
	m._process(.6)
	desk.check(w.data.support_lift==0. and absf(ears.target(other).y-raised.y)>.4,"either paper ear folds the coupled pair")
	desk.check(face.x>m.paper_section(-1.6).x+.10 and m.paper_section(.12)==nip,"sheet follows raised supports without displacing the platen nip")
	var tip:Vector3=m.vec(ears.spec.targets[other][1])
	var carry=Vector3.RIGHT*m.travel
	anchor=ears.screen(ears.target(other))
	var half=ears.screen(carry+ears.support_transform(other,.6)*tip)
	Pointer.mouse(m,anchor,true)
	Pointer.move(m,half)
	m._process(.04)
	desk.check(m.grab_owner==ears and absf(ears.support_pose-.6)<.06,"right ear follows the grabbed point through its hinge arc")
	var cancel=InputEventMouseButton.new()
	cancel.button_index=MOUSE_BUTTON_RIGHT
	cancel.pressed=true
	cancel.position=half
	m._gui_input(cancel)
	cancel.pressed=false
	m._gui_input(cancel)
	desk.check(w.data.support_lift==0. and is_zero_approx(ears.support_pose),"cancel returns both supports to their captured position")
	m._process(.3)
	Pointer.mouse(m,anchor,true)
	Pointer.move(m,half)
	Pointer.mouse(m,half,false)
	m._process(.5)
	desk.check(w.data.support_lift==1. and ears.support_pose==1.,"releasing a dragged ear settles to the nearest stop")
	anchor=ears.screen(ears.target(other))
	Click.click(m,anchor)
	Click.click(m,anchor,true)
	desk.check(w.data.support_lift==1.,"double-click restores the raised ready-to-type supports")
	w.data.half=76
	desk.sync()
	var spent:Vector2=m.paper_section(1.45)
	w.data.support_lift=0.
	m._process(.6)
	desk.check(spent.x>m.paper_section(1.45).x+.12,"the printed end of a long sheet is supported after passing the upper bail")
	w.new_stock("Postcard")
	desk.sync()
	var edge=(w.dimensions().y-w.BASE)*.025/w.PITCH
	var short_edge:Vector2=m.paper_section(-edge)
	w.data.support_lift=1.
	m._process(.6)
	desk.check(short_edge.distance_to(m.paper_section(-edge))<.012,"a short postcard that ends before the hinge cannot be lifted by the ears")
	w.data.paper_loose=true
	w.data.paper_side=.65
	w.data.paper_skew=.17
	desk.sync()
	m._process(.2)
	var clear:Vector2=m.paper_section(-1.7,1.,Vector2(.65,1.4))
	w.data.support_lift=0.
	m._process(.6)
	desk.check(clear.distance_to(m.paper_section(-1.7,1.,Vector2(.65,1.4)))<.012,"a loose sheet missing both arms keeps its free curve")
	w.reset()
	desk.sync()
	m.set_cut(false)
	m._process(.4)

