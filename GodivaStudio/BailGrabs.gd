extends RefCounted
## Pull, slide, or hold carriage fittings directly in their projected axes.
const BAIL="Paper bail"
const LOCK="Carriage centering latch"
const ROLLERS=["Left bail roller","Right bail roller"]
const SETTERS=["Flying margin left","Flying margin right"]
const PITCH=.025
const ROLLER_SPAN=2.44
const ROLLER_GAP=.19/ROLLER_SPAN
var m
var desk
var spec={}
var tracks={}
var active=""
var start:Vector2
var start_value=0.
var start_col=0.
var stock_token
var carriage_shift=0.
var starting_bypass=false
var start_margin=0
var started_locked=false
var moving=false
var margin_release_owned=false
var lock_trip=0.
var lock_catch=0.
var support_pose:=0.
var start_pose:=0.
var support_grip:=Vector3.ZERO
var rest_paths={}
var sheet_profile=preload("res://PaperSupportProfile.gd").new()
var profile_pose:=-1.
var profile_stock:=""
var support_span:=Vector2(-.59,.47)
var support_lip:=Vector2(1.415,-1.424)

func pose_at(poses:Array,f:float)->Transform3D:
	var sample=clampf(f,0.,1.)*(poses.size()-1)
	var i=mini(int(sample),poses.size()-2)
	return poses[i].interpolate_with(poses[i+1],sample-i)

func support_transform(label:String,f:float)->Transform3D:
	return pose_at(tracks.support[spec.targets[label][0]],f)

func prepare_sheet(writer):
	if profile_stock==writer.data.paper and profile_pose==support_pose:return
	var path=PackedVector2Array()
	var label="Paper support left"
	if rest_paths.has(label):
		var transform=support_transform(label,support_pose)
		for point in rest_paths[label]:
			var actual:Vector3=transform*point
			path.append(Vector2(actual.y,actual.z))
	elif support_pose>0.:
		path.append(support_lip+Vector2(.46,-.34)*support_pose)
	sheet_profile.rebuild(writer,path,support_span,support_lip)
	profile_pose=support_pose
	profile_stock=writer.data.paper

func nearest_support_point(label:String,pos:Vector2)->Vector3:
	var points:PackedVector3Array=rest_paths[label]
	var part=m.groups[spec.targets[label][0]]
	var best=points[-1]
	var distance=INF
	for i in range(1,points.size()):
		var a=screen(part.transform*points[i-1])
		var b=screen(part.transform*points[i])
		var segment=b-a
		var f=clampf((pos-a).dot(segment)/maxf(segment.length_squared(),.0001),0.,1.)
		var gap=pos.distance_squared_to(a.lerp(b,f))
		if gap<distance:
			best=points[i-1].lerp(points[i],f)
			distance=gap
	return best

func drag_support(delta:Vector2):
	# Follow the same projected hinge sweep as the grabbed point. A tip
	# seen from the side traces an arc and can pass behind the hinge.
	var carry=Vector3.RIGHT*m.travel
	var goal=screen(carry+support_transform(active,start_pose)*support_grip)+delta
	var poses:Array=tracks.support[spec.targets[active][0]]
	var best=support_pose
	var distance=INF
	for i in range(1,poses.size()):
		var a=screen(carry+poses[i-1]*support_grip)
		var b=screen(carry+poses[i]*support_grip)
		var edge=b-a
		var f=clampf((goal-a).dot(edge)/maxf(edge.length_squared(),.0001),0.,1.)
		var fraction=(i-1+f)/(poses.size()-1)
		var error=goal.distance_squared_to(a.lerp(b,f))+.02*absf(fraction-support_pose)
		if error<distance:
			best=fraction
			distance=error
	support_pose=best

func setup(machine,controller):
	m=machine
	desk=controller
	spec=m.writer.meta.get("bail_grabs",{})
	for channel in spec.get("tracks",{}):
		tracks[channel]=m.load_actuator_tracks(spec.tracks[channel])
	var contact:Dictionary=spec.get("support_contact",{})
	if contact.has("lip"):
		support_lip=Vector2(contact.lip[0],contact.lip[1])
		support_span=Vector2(contact.x[0],contact.x[1])
	for label in contact.get("rest_paths",{}):
		var path=PackedVector3Array()
		for raw in contact.rest_paths[label]:path.append(m.vec(raw))
		rest_paths[label]=path
	support_pose=roundf(float(m.writer.data.support_lift))
	profile_pose=-1.
	m.update_sheet()

func screen(world_point:Vector3)->Vector2:
	return m.camera.unproject_position(world_point)

func project(delta:Vector2,axis:Vector3)->float:
	var path=screen(axis)-screen(Vector3.ZERO)
	return delta.dot(path)/maxf(path.length_squared(),.01)

func target(label:String)->Vector3:
	var ref:Array=spec.targets[label]
	return m.groups[ref[0]].transform*m.vec(ref[1])

func hit(best:Dictionary,label:String,distance:float,radius:float,tip:String):
	if distance<radius and distance<float(best.get("distance",INF)):
		best.merge({"label":label,"distance":distance,"tip":tip},true)

func pick(pos:Vector2,radius:float)->Dictionary:
	var best={}
	if spec.is_empty():return best
	for side in ["left","right"]:
		var key="roller_"+side
		var label="Left bail roller" if side=="left" else "Right bail roller"
		hit(best,label,pos.distance_to(screen(m.groups[key].position)),radius,"Slide the roller along the bail")
	for label in SETTERS:
		hit(best,label,pos.distance_to(screen(m.carriage_rig.point(label))),radius,"Pull the setter and drag the carriage to choose a margin")
	for label in spec.targets:
		var tip="Click either ear to raise or stow both paper supports. Drag to swing them between stops." if label.begins_with("Paper support") else "Hold to center the carriage; pull right while held to unlock"
		var grip=target(label)
		if rest_paths.has(label):
			grip=m.groups[spec.targets[label][0]].transform*nearest_support_point(label,pos)
		hit(best,label,pos.distance_to(screen(grip)),radius,tip)
	# The rod occupies a line on screen. Prefer a tyre over the rod under it.
	var left:Vector3=m.groups.roller_left.position
	var right:Vector3=m.groups.roller_right.position
	var mid=Vector3(m.travel,(left.y+right.y)*.5,(left.z+right.z)*.5)
	var a=screen(mid-Vector3.RIGHT*1.36)
	var b=screen(mid+Vector3.RIGHT*1.36)
	if (b-a).length_squared()>.01:
		var nearest=Geometry2D.get_closest_point_to_segment(pos,a,b)
		var distance=pos.distance_to(nearest)
		if not best.get("label","") in ROLLERS:
			hit(best,BAIL,distance+2.,radius*.72,"Lift or lower the complete paper bail")
	return best

func begin(label:String,pos:Vector2,_shifted:bool):
	active=label
	start=pos
	moving=false
	var w=m.writer
	stock_token=w.raster
	carriage_shift=0.
	starting_bypass=w.data.margin_released
	start_col=w.carriage_column()
	started_locked=bool(w.data.get("center_locked",false))
	margin_release_owned=false
	if label==BAIL:start_value=float(w.data.get("bail_lift",int(w.data.bail_up)))
	elif label in ROLLERS:start_value=float(w.data["bail_"+roller_side()])
	elif label.begins_with("Paper support"):
		start_value=float(w.data.support_lift)
		start_pose=support_pose
		support_grip=nearest_support_point(label,pos) if rest_paths.has(label) else m.vec(spec.targets[label][1])
	elif label in SETTERS:
		start_margin=int(w.data[setter_side()])
		m.carriage_rig.set_control(label,true)
		if not started_locked:w.set_flying_margin(setter_side())
	elif label==LOCK:
		if not started_locked and not w.carriage_held():
			w.set_carriage_release("right",true)
			margin_release_owned=true
	desk.changed()

func roller_side()->String:return "left" if active==ROLLERS[0] else "right"
func setter_side()->String:return "left" if active==SETTERS[0] else "right"

func set_bail(value:float):
	m.writer.data.bail_lift=clampf(value,0.,1.)
	m.writer.data.bail_up=m.writer.data.bail_lift>=.5

func drag(pos:Vector2):
	if active.is_empty():return
	if m.writer.raster!=stock_token:finish(true);return
	var d=pos-start
	if not moving and d.length()<3.:return
	moving=true
	var w=m.writer
	if active==BAIL:
		var arm=m.fittings.roller_left-m.fittings.bail
		set_bail(start_value+project(d,arm.rotated(Vector3.RIGHT,-.74)-arm))
	elif active in ROLLERS:
		var val=start_value+project(d,Vector3.RIGHT*ROLLER_SPAN)
		if active==ROLLERS[0]:w.data.bail_left=clampf(val,0.,maxf(0.,w.data.bail_right-ROLLER_GAP))
		else:w.data.bail_right=clampf(val,minf(1.,w.data.bail_left+ROLLER_GAP),1.)
	elif active.begins_with("Paper support"):
		drag_support(d)
	elif active in SETTERS and not started_locked:
		if not w.carriage_held():
			w.set_carriage_release(setter_side(),true)
			margin_release_owned=true
		var col=start_col-project(d,Vector3.RIGHT*PITCH)
		if setter_side()=="left":col=minf(col,w.data.right-1)
		else:col=maxf(col,w.data.left+1)
		slide_to(col)
		w.set_flying_margin(setter_side())
	elif active==LOCK and started_locked and project(d,Vector3.RIGHT*PITCH)>=2.:
		if w.data.center_locked:
			var before=w.carriage_column()
			w.data.center_locked=false
			w.move_col(w.bank_center_column()-2)
			carriage_shift+=w.carriage_column()-before
	desk.changed()

func slide_to(value:float):
	var w=m.writer
	var before=w.carriage_column()
	w.slide_carriage(value)
	carriage_shift+=w.carriage_column()-before

func finish(cancelled:bool):
	if active.is_empty():return
	var w=m.writer
	var same_sheet=w.raster==stock_token
	if active in SETTERS:m.carriage_rig.set_control(active,false)
	if cancelled and same_sheet:
		if active==BAIL:set_bail(start_value)
		elif active in ROLLERS:w.data["bail_"+roller_side()]=start_value
		elif active.begins_with("Paper support"):
			w.data.support_lift=start_value
			support_pose=start_value
		elif active==LOCK or active in SETTERS:
			if active==LOCK:w.data.center_locked=false
			else:w.data[setter_side()]=start_margin
			if not is_zero_approx(carriage_shift):
				var previous=w.carriage_column()-carriage_shift
				if w.carriage_held():w.slide_carriage(previous)
				else:w.move_col(roundi(previous))
			if active==LOCK and started_locked:
				w.move_col(w.bank_center_column())
				w.data.center_locked=true
			if is_equal_approx(w.carriage_column(),start_col):w.data.margin_released=starting_bypass
	elif not cancelled and same_sheet and not moving:
		if active==BAIL:set_bail(1. if start_value<.5 else 0.)
		elif active.begins_with("Paper support"):w.data.support_lift=1. if start_value<.5 else 0.
	elif not cancelled and same_sheet and moving and active.begins_with("Paper support"):
		w.data.support_lift=roundf(support_pose)
	if margin_release_owned:
		w.set_carriage_release(setter_side() if active in SETTERS else "right",false)
	margin_release_owned=false
	active=""
	stock_token=null
	desk.changed()

func reset_default(label:String):
	var w=m.writer
	var d=w.data
	match label:
		BAIL:set_bail(0.)
		"Left bail roller":d.bail_left=minf(.22,float(d.bail_right)-ROLLER_GAP)
		"Right bail roller":d.bail_right=maxf(.78,float(d.bail_left)+ROLLER_GAP)
		"Flying margin left":d.left=mini(0,int(d.right)-1)
		"Flying margin right":
			d.right=maxi(67 if d.paper=="Letter" else 41,int(d.left)+1)
			if d.col<=d.right:d.margin_released=false
		LOCK:d.center_locked=false
		_:
			if not label.begins_with("Paper support"):return
			d.support_lift=1.
	desk.changed()

func update(dt:float):
	if spec.is_empty():return
	var w=m.writer
	if active!="" and w.raster!=stock_token:finish(true)
	if not (moving and active.begins_with("Paper support")):
		support_pose=move_toward(support_pose,float(w.data.support_lift),dt*5.)
	if profile_pose!=support_pose:m.update_sheet()
	var centering=active==LOCK and not started_locked and not w.data.get("center_locked",false)
	if centering:
		var col=w.carriage_column()
		var goal=float(w.bank_center_column())
		var next=move_toward(col,goal,dt*48.)
		slide_to(next)
		if is_equal_approx(next,goal):
			w.data.center_locked=true
			if margin_release_owned:w.set_carriage_release("right",false)
			margin_release_owned=false
		desk.changed()
	var locked:bool=w.data.get("center_locked",false)
	lock_trip=move_toward(lock_trip,1. if active==LOCK else 0.,dt*12.)
	var desired=1. if locked else (.42 if centering else 0.)
	if started_locked and active==LOCK:desired=0.
	lock_catch=move_toward(lock_catch,desired,dt*13.)
	var strengths={"press":lock_trip,"catch":lock_catch,"support":support_pose}
	var carry=Transform3D(Basis.IDENTITY,Vector3.RIGHT*m.travel)
	for label in strengths:
		for part in tracks[label]:
			var poses:Array=tracks[label][part]
			m.groups[part].transform=carry*pose_at(poses,strengths[label])
