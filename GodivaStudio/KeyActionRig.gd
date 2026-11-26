extends RefCounted

var groups={}
var tracks={}
var previous={}
var lit=""
var overlay=StandardMaterial3D.new()


func setup(machine):
	groups=machine.groups
	overlay.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.albedo_color=Color(1.,.66,.19,.34)
	overlay.no_depth_test=true
	overlay.render_priority=1
	for key in machine.writer.meta.key_action:
		tracks[key]=machine.load_actuator_tracks(machine.writer.meta.key_action[key])

func update(depths:Dictionary,shift_height:float):
	for key in tracks:
		var depth=clampf(float(depths.get(key,0.)),0.,1.)*12.
		var state=Vector2(depth,shift_height)
		# The generic key animation uses a translation; replace it with the
		# native pivot even on the final frame of a stroke.
		if previous.get(key,Vector2(-1,-1)).is_equal_approx(state) and not depths.has(key):continue
		previous[key]=state
		var i=mini(11,floori(depth))
		for group in tracks[key]:
			var poses=tracks[key][group]
			var lower=poses[i].interpolate_with(poses[i+1],depth-i)
			var upper=poses[i+13].interpolate_with(poses[i+14],depth-i)
			groups[group].transform=lower.interpolate_with(upper,shift_height)

func highlight(key:String):
	if not tracks.has(key):key=""
	if lit==key:return
	for name in [lit,key]:
		if name.is_empty():continue
		var pieces=tracks[name].keys()
		pieces.append("bar:"+name)
		for group in pieces:
			groups[group].get_child(0).material_overlay=overlay if name==key else null
	lit=key
