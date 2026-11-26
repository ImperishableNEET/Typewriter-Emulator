extends RefCounted

var host
var tracks:Dictionary
var detent:=1.
var previous:=Vector2(-1.,-1.)

func setup(machine):
	host=machine
	var manifest:Dictionary=machine.writer.meta.touch_rig
	tracks=machine.load_actuator_tracks(manifest.tracks)
	detent=float(machine.writer.data.touch_regulator)

func update(dt:float,setting:int,key_travel:float):
	detent=move_toward(detent,float(setting),dt*14.)
	var pose=Vector2(detent,clampf(key_travel,0.,1.)*4.)
	if pose.is_equal_approx(previous):return
	previous=pose
	var lower=mini(2,floori(detent))
	var step=mini(3,floori(pose.y))
	for part in tracks:
		var samples:Array=tracks[part]
		var a=lower*5+step
		var b=a+5
		var at_lower:Transform3D=samples[a].interpolate_with(samples[a+1],pose.y-step)
		var at_upper:Transform3D=samples[b].interpolate_with(samples[b+1],pose.y-step)
		host.groups[part].transform=at_lower.interpolate_with(at_upper,detent-lower)
