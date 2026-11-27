extends SubViewportContainer
## Operator viewport for Hilda's articulated GLB. Writer owns the strike and
## sheet state. The escapement steps after the slug touches the ribbon.
signal key_pressed(shifted: bool)
signal printing_key_pressed(key: String, shifted: bool)
signal carriage_control_requested(control: String, value: float)

const PLATEN_CENTER := Vector3(0, 1.12, -1.03)
const PAPER_RADIUS := 0.122
const COLUMN_PITCH := 0.0254
const CONTACT_PHASE := 0.46
const CAMERA_TARGET := Vector3(0.32, 0.99, -0.12)
const PAPER_SHADER := """
shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform sampler2D page : source_color, filter_linear;
void fragment() {
	vec3 inked = texture(page, UV).rgb;
	vec3 stock = texture(page, vec2(0.0)).rgb;
	ALBEDO = FRONT_FACING ? inked : mix(stock, inked, 0.06);
	ROUGHNESS = 1.0;
}
"""
const PIVOTS := [&"HildaCarriage", &"HildaRibbonCover", &"HildaShiftBasket",
	&"HildaLeftShift", &"HildaRightShift", &"HildaPlatenRoll", &"HildaReturnLever",
	&"HildaLineSpacingSelector", &"HildaPaperSupport", &"HildaPaperSupportSlide"]
const SERVICE_HANDLES := {
	"Left knob":"HildaPlatenKnobLeft", "Right knob":"HildaPlatenKnobRight",
	"Return":"HildaReturnGrip", "Spacing":"HildaLineSpacingHandle"}
const TAB_PARTS := {
	"tab": ["Key 1-13", "Key 1-13 legend 0", "Key 1-13 stem", "Key 1-13 lever"],
	"tab_clear": ["Tab clear", "Tabulator clear legend"],
	"tab_set": ["Tab set", "Tabulator set legend"]}
const RETURN_SWING := 0.43
const SELECTOR_STEP := 0.16

var writer
var view := SubViewport.new()
var world := Node3D.new()
var camera := Camera3D.new()
var model: Node3D
var pivots: Dictionary = {}
var rest: Dictionary = {}
var key_meshes: Array[MeshInstance3D] = []
var caps: Dictionary = {}
var actions: Dictionary = {}
var linkage = preload("res://machines/hilda/HildaLinkage.gd").new()
var posed_key := ""
var spacebar: MeshInstance3D
var spacebar_rest := Transform3D.IDENTITY
var ribbon_runs: Array[Dictionary] = []
var ribbon_forks: Array[Dictionary] = []
var sheet := MeshInstance3D.new()
var sheet_material := ShaderMaterial.new()
var last_texture: Texture2D
var paper_shape := Vector3(-1, -1, -1)
var queue: Array[Dictionary] = []
var elapsed := 0.0
var cover_open := false
var cover_depth := 0.0
var support_setting := 0
var support_travel := 0.0
var cover_hinge := Vector3.ZERO
var shift_held := false
var shift_depth := 0.0
var yaw := 0.22
var elevation := 0.48
var distance := 7.45
var rear_view := false
var carriage_view := false
var rear_fill:DirectionalLight3D
var orbiting := false
var handle_grab := ""
var registration_pulled := false
var pull_axis := Vector2.ZERO
var left_knob:Node3D
var knob_home:Vector3
var ratchet:Node3D
var ratchet_home:Transform3D
var grab_start := Vector2.ZERO
var grab_axis := Vector2.UP
var grab_start_feed := 0.0
var grab_start_detent := 0
var grab_moved := false
var grab_travel_px := 12.0
var selected_detent := -1
var return_preload := 0.0
var control_meshes: Dictionary = {}
var handle_faces: Dictionary = {}
var tab_pivots: Dictionary = {}
var tab_held := ""
var tab_playing := ""
var tab_depth := 0.0

func setup(w) -> void:
	writer = w
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	view.own_world_3d = true
	view.msaa_3d = Viewport.MSAA_2X
	view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(view)
	view.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#29362f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e8f0f0")
	env.ambient_light_energy = 0.31
	env.ambient_light_sky_contribution = 0.0
	var surroundings := WorldEnvironment.new()
	surroundings.environment = env
	world.add_child(surroundings)
	_light(Vector3(-3, 5, 4), 0.19, Color("#fff4e5"), true)
	rear_fill = _light(Vector3(2, 2, -4), 0.075, Color("#f2eee6"), false)
	world.add_child(camera)
	camera.current = true
	camera.fov = 35
	camera.near = 0.035
	_frame()
	var scene := load(str(writer.machine_profile.geometry_path)) as PackedScene
	if scene == null:
		push_error("Hilda operator geometry failed to load: " + str(writer.machine_profile.geometry_path))
		return
	model = scene.instantiate() as Node3D
	world.add_child(model)
	for label in PIVOTS:
		var node := model.find_child(label, true, false) as Node3D
		if node:
			pivots[label] = node
			rest[label] = node.transform
	_register_printing_keys()
	_register_tab_controls()
	for label in SERVICE_HANDLES:
		var handle := model.find_child(SERVICE_HANDLES[label], true, false) as Node3D
		if handle:
			var meshes := handle.find_children("*", "MeshInstance3D", true, false)
			if handle is MeshInstance3D: meshes.push_front(handle)
			control_meshes[label] = meshes
			for mesh:MeshInstance3D in meshes:
				handle_faces[mesh] = mesh.mesh.get_faces()
	left_knob = model.find_child("HildaPlatenKnobLeft",true,false) as Node3D
	if left_knob: knob_home = left_knob.position
	ratchet = model.find_child("HildaPlatenRatchet",true,false) as Node3D
	if ratchet: ratchet_home = ratchet.transform
	linkage.setup(model, actions)
	spacebar = model.find_child("Spacebar", true, false) as MeshInstance3D
	if spacebar:
		spacebar_rest = spacebar.transform
		caps["Space"] = spacebar
	var cover: Node3D = pivots.get(&"HildaRibbonCover")
	if cover:
		cover_hinge = _rear_cover_hinge(cover)
	for web in model.find_children("Ribbon web*", "MeshInstance3D", true, false):
		var box: AABB = web.transform * web.get_aabb()
		var side := signf(box.get_center().x)
		var edge := box.end.x if side > 0 else box.position.x
		ribbon_runs.append({"web":web, "home":web.transform, "side":side,
			"anchor":Vector3(edge, box.get_center().y, box.get_center().z)})
	for fork in model.find_children("Ribbon fork*", "MeshInstance3D", true, false):
		ribbon_forks.append({"fork":fork, "home":fork.position})
	var carriage: Node3D = pivots.get(&"HildaCarriage", model)
	carriage.add_child(sheet)
	# The sheet's mounting points use model coordinates even if the imported
	# carriage pivot lives at its shaft, away from the model origin.
	sheet.global_transform = model.global_transform
	var shader := Shader.new()
	shader.code = PAPER_SHADER
	sheet_material.shader = shader
	sheet.material_override = sheet_material
	_pose_support()
	sync()

func set_paper_support(setting: int) -> void:
	support_setting = clampi(setting, 0, 2)

func _pose_support() -> void:
	# Local X is across the carriage and local Y is up in the imported GLB.
	# Retract the inner ruler before laying the folded channel into its recess.
	var hinge: Node3D = pivots[&"HildaPaperSupport"]
	var inner: Node3D = pivots[&"HildaPaperSupportSlide"]
	var folded := 1.0 - smoothstep(0.0, 1.0, support_travel)
	var home: Transform3D = rest[&"HildaPaperSupport"]
	var flat := Basis(Vector3.RIGHT, -PI / 2.0) * Basis(Vector3.BACK, -PI / 2.0)
	hinge.transform = home * Transform3D(Basis.IDENTITY.slerp(flat, folded), Vector3.ZERO)
	inner.position = rest[&"HildaPaperSupportSlide"].origin - Vector3.UP * (1.17 * (1.0 - smoothstep(1.0, 2.0, support_travel)))

func _register_printing_keys() -> void:
	var nodes := {}
	var part_names: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://machines/hilda/part_names.json"))
	for node in model.find_children("*", "Node3D", true, false):
		nodes[node.name] = node
	for label in writer.meta.bars:
		var prefix := "Hilda" + str(part_names.get(label, label))
		var key := StringName(prefix + "Key")
		var link := StringName(prefix + "Link")
		var bar := StringName(prefix + "Bar")
		var cap := nodes.get(StringName(prefix + "Keycap")) as MeshInstance3D
		if not cap or not nodes.has(key) or not nodes.has(link) or not nodes.has(bar):
			push_error("Hilda GLB has an incomplete printing action for " + str(label))
			continue
		actions[label] = [key, link, bar]
		caps[label] = cap
		for pivot in actions[label]:
			pivots[pivot] = nodes[pivot]
			rest[pivot] = nodes[pivot].transform
		# Keep the first-action fixture's H cap at index zero.
		if label == "H": key_meshes.push_front(cap)
		else: key_meshes.append(cap)

func cap_for_key(label: String) -> MeshInstance3D:
	return caps.get(label)

func _register_tab_controls() -> void:
	# Photo 09 identifies all three caps. The GLB stores them as individual
	# frame children. Group each cap with its legend and any exposed lever.
	for label: String in TAB_PARTS:
		var parts: Array = TAB_PARTS[label]
		var cap := model.find_child(parts[0], true, false) as MeshInstance3D
		if not cap:
			push_error("Missing Hilda tab control: " + label)
			continue
		var pivot := Node3D.new()
		cap.get_parent().add_child(pivot)
		# The upper key uses the printing-key fulcrum. Its position and the
		# travel of the front paddles are estimates from the resting geometry.
		pivot.position = Vector3(cap.position.x, 0.36, -0.10)
		for part_name: String in parts:
			var part := model.find_child(part_name, true, false) as Node3D
			if part: part.reparent(pivot, true)
		tab_pivots[label] = pivot
		control_meshes[label] = [cap]
		handle_faces[cap] = cap.mesh.get_faces()

func _tab_pose(playing: String, depth: float) -> void:
	tab_playing = playing
	tab_depth = depth
	for label: String in tab_pivots:
		var amount := 1.0 if label == tab_held else (depth if label == playing else 0.0)
		var pivot: Node3D = tab_pivots[label]
		pivot.rotation.x = amount * (0.09 if label == "tab" else 0.037)

func _light(at: Vector3, energy: float, color: Color, shadows: bool) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.position = at
	light.look_at(Vector3.ZERO)
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	return light

func _frame() -> void:
	var target := Vector3(0.2, 0.79, -0.72) if rear_view else CAMERA_TARGET
	if carriage_view and pivots.has(&"HildaCarriage"):
		var translation: Vector3 = pivots[&"HildaCarriage"].position - rest[&"HildaCarriage"].origin
		target = Vector3(-1.52, 1.18, -0.48) + translation
	var aspect := maxf(size.x / maxf(size.y, 1.0), 0.5)
	var fit := maxf(1.0, 1.28 / aspect)
	camera.position = target + distance * fit * Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	camera.look_at(target)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(camera) and camera.is_inside_tree():
		_frame()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not tab_held.is_empty():
		tab_held = ""
		_tab_pose(tab_playing, tab_depth)

func set_rear_view(enabled: bool) -> void:
	carriage_view = false
	rear_view = enabled
	yaw = PI if enabled else 0.22
	elevation = 0.14 if enabled else 0.48
	distance = 6.5 if enabled else 7.45
	rear_fill.light_energy = 0.42 if enabled else 0.075
	_frame()

func set_carriage_view(enabled: bool) -> void:
	set_rear_view(false)
	carriage_view = enabled
	if enabled:
		yaw = -1.05
		elevation = 0.76
		distance = 3.05
	_frame()

func _rotate_pivot(id: StringName, radians: float) -> void:
	if pivots.has(id):
		var home: Transform3D = rest[id]
		pivots[id].transform = home.rotated_local(Vector3.RIGHT, radians)

func _offset_pivot(id: StringName, offset: Vector3) -> void:
	if pivots.has(id):
		var node: Node3D = pivots[id]
		var home: Transform3D = rest[id]
		node.position = home.origin + offset

func set_shift(held: bool) -> void:
	shift_held = held

func set_cover_open(open: bool) -> void:
	cover_open = open

func _rear_cover_hinge(cover: Node3D) -> Vector3:
	# Photograph 06 shows the front edge standing above the keys while the
	# rear edge stays beside the carriage. Estimate the hinge from that edge.
	var meshes := cover.find_children("*", "MeshInstance3D", true, false)
	if cover is MeshInstance3D:
		meshes.append(cover)
	var bounds := AABB()
	var first := true
	for child in meshes:
		var box: AABB = (cover.global_transform.affine_inverse() * child.global_transform) * child.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return Vector3(bounds.get_center().x, bounds.position.y, bounds.position.z)

func _surface_point(x: float, depth: float) -> Vector3:
	# Follow the platen down the front, under its belly, then up the rear
	# paper table. The leading edge rises above the ribbon as lines feed.
	if depth < 0.0:
		return PLATEN_CENTER + Vector3(x, -depth, PAPER_RADIUS)
	var arc := depth / PAPER_RADIUS
	if arc <= PI:
		return PLATEN_CENTER + Vector3(x, -PAPER_RADIUS * sin(arc), PAPER_RADIUS * cos(arc))
	var tail := depth - PI * PAPER_RADIUS
	# A raised rest holds the back of a long sheet upright at the contact line.
	var free_tail := PLATEN_CENTER + Vector3(x, tail * 0.96, -PAPER_RADIUS - tail * 0.28)
	if support_travel > 0.8 and tail > 0.78:
		var at_rest := Vector3(x, 0.78 * 0.96, -PAPER_RADIUS - 0.78 * 0.28)
		var held_tail := PLATEN_CENTER + at_rest + Vector3.UP * (tail - 0.78)
		return free_tail.lerp(held_tail, smoothstep(0.8, 1.0, support_travel))
	return free_tail

func _shape_sheet(dims: Vector2i, half_line: float) -> void:
	var units_per_pixel := COLUMN_PITCH / float(writer.PITCH)
	var total_height := dims.y * units_per_pixel
	var width := dims.x * units_per_pixel
	var printed_to := (float(writer.BASE) + half_line * float(writer.LEADING) * 0.5) * units_per_pixel
	var heights: Array[float] = [0.0]
	for segment in 25:
		var height := printed_to + PI * PAPER_RADIUS * segment / 24.0
		if height > 0 and height < total_height:
			heights.append(height)
	var contact_height := printed_to + PI * PAPER_RADIUS + 0.78
	if contact_height < total_height and contact_height > 0:
		heights.append(contact_height)
	heights.append(total_height)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var previous := 0.0
	for i in range(1, heights.size()):
		var current := heights[i]
		for corner in [Vector2(0, previous), Vector2(1, previous), Vector2(1, current),
				Vector2(0, previous), Vector2(1, current), Vector2(0, current)]:
			mesh.set_uv(Vector2(corner.x, corner.y / total_height))
			mesh.add_vertex(_surface_point((corner.x - 0.5) * width, corner.y - printed_to))
		previous = current
	mesh.generate_normals()
	sheet.mesh = mesh.commit()

func _place_column(column: float) -> void:
	var dims: Vector2i = writer.dimensions()
	var center_pixel := float(writer.MARGIN) + (column + 0.5) * float(writer.PITCH)
	var travel := (dims.x * 0.5 - center_pixel) * COLUMN_PITCH / float(writer.PITCH)
	_offset_pivot(&"HildaCarriage", Vector3.RIGHT * travel)
	if carriage_view: _frame()

func spacing_detent() -> int:
	if writer.data.free_platen: return 3
	return clampi(roundi((float(writer.data.spacing)-1.0)*2.0), 0, 2)

func _set_return(depth: float) -> void:
	var id := &"HildaReturnLever"
	if pivots.has(id):
		pivots[id].transform = (rest[id] as Transform3D).rotated_local(Vector3.UP, RETURN_SWING * depth)

func _feed_pose(half: float, platen_half: float) -> void:
	var dims: Vector2i = writer.dimensions()
	var shape := Vector3(dims.x, dims.y, half)
	if shape != paper_shape:
		paper_shape = shape
		_shape_sheet(dims, half)
	# Match tangential travel of the cylinder to the arc length of the fed sheet.
	var half_pitch := 0.5 * float(writer.LEADING) * COLUMN_PITCH / float(writer.PITCH)
	_rotate_pivot(&"HildaPlatenRoll", -platen_half * half_pitch / PAPER_RADIUS)
	if ratchet:
		# Cancel the platen's accumulated register correction on the toothed wheel.
		var offset:float = writer.data.platen_half - writer.data.ratchet_half
		ratchet.transform = Transform3D(Basis(Vector3.RIGHT,offset*half_pitch/PAPER_RADIUS),Vector3.ZERO)*ratchet_home

func sync() -> void:
	if not model or not writer:
		return
	sheet.visible = bool(writer.data.get("sheet_loaded", true))
	if last_texture != writer.texture:
		last_texture = writer.texture
		sheet_material.set_shader_parameter("page", last_texture)
	var detent := spacing_detent()
	if detent != selected_detent:
		selected_detent = detent
		_rotate_pivot(&"HildaLineSpacingSelector", -SELECTOR_STEP * detent)
	if queue.is_empty():
		_place_column(float(writer.data.col))
		_feed_pose(float(writer.data.half), float(writer.data.platen_half))
		_set_return(return_preload)

func strike(event: Dictionary, on_contact: Callable) -> void:
	if event.is_empty():
		return
	queue.append({"event": event, "callback": on_contact, "made_contact": false,
		"half":float(writer.data.half), "platen":float(writer.data.platen_half)})
	if queue.size() == 1:
		elapsed = 0.0
		_place_column(float(event.col))

func space_advance(from_column: int) -> void:
	# Spaces use the escapement but do not lift the ribbon or strike the page.
	strike({"key":"Space", "col":from_column, "shift":shift_held,
		"motion_duration":0.085}, Callable())

func carriage_motion(kind: String, from_col: float, from_half: float, from_platen: float) -> void:
	if kind not in ["return", "platen"] and not TAB_PARTS.has(kind): return
	var to_col := float(writer.data.col)
	var to_half := float(writer.data.half)
	var to_platen := float(writer.data.platen_half)
	# A long return takes longer than a standalone line feed. Store both ends so
	# a following keystroke or second return can't move the goal mid-stroke.
	var duration := 0.23 + minf(absf(from_col-to_col)*0.005, 0.36) if kind == "return" else 0.075
	if kind == "tab":
		duration = 0.11 + minf(absf(to_col-from_col)*0.005, 0.32)
	elif kind in ["tab_set", "tab_clear"]:
		duration = 0.11
	var event := {"key":kind, "col":from_col, "motion_duration":duration}
	var stroke := {"event":event, "callback":Callable(), "made_contact":true,
		"half":from_half, "platen":from_platen, "to_half":to_half, "to_platen":to_platen,
		"to_col":to_col, "preload":return_preload}
	return_preload = 0.0
	# Knob drags emit small values at pointer speed. Update their current target
	# in place so the mechanism follows the hand without building up lag.
	if kind == "platen" and queue.size() == 1 and queue[0].event.key == "platen":
		stroke.half = paper_shape.z
		stroke.platen = lerpf(queue[0].platen, queue[0].to_platen,
			smoothstep(0, 1, elapsed / float(queue[0].event.motion_duration)))
		queue[0] = stroke
		elapsed = 0.0
		return
	queue.append(stroke)
	if queue.size() == 1:
		elapsed = 0.0
		_place_column(from_col)
		_feed_pose(from_half, from_platen)

func _contact(stroke: Dictionary) -> void:
	if stroke.made_contact:
		return
	stroke.made_contact = true
	var callback: Callable = stroke.callback
	if callback.is_valid():
		callback.call()

func flush() -> void:
	# Scene switches and saves may occur while the slug is still in flight.
	for stroke in queue:
		_contact(stroke)
	queue.clear()
	elapsed = 0.0
	return_preload = 0.0
	tab_held = ""
	_tab_pose("", 0.0)
	_pose(posed_key, 0.0, 0.0, "")
	sync()

func _pose(label: String, key_depth: float, bar_depth: float, ink: String) -> void:
	if spacebar and (label == "Space" or posed_key == "Space"):
		var displacement := Vector3.DOWN * (0.065 * key_depth if label == "Space" else 0.0)
		spacebar.transform = spacebar_rest.translated(displacement)
	if label != posed_key:
		for id in actions.get(posed_key, []):
			pivots[id].transform = rest[id]
		linkage.pose(posed_key)
		posed_key = label
	if actions.has(label):
		var action: Array = actions[label]
		_rotate_pivot(action[0], 0.07 * key_depth)
		_rotate_pivot(action[1], 0.22 * key_depth)
		_rotate_pivot(action[2], -2.54 * bar_depth)
		linkage.pose(label)
	# The guide lifts the selected ribbon band into the print line while
	# both spool ends of the ribbon stay at the same height.
	var lift := (0.122 if ink == "Red" else 0.070) * smoothstep(0.10, 0.81, key_depth) if actions.has(label) else 0.0
	for run in ribbon_runs:
		var anchor: Vector3 = run.anchor
		var turn := Basis(Vector3.BACK, -run.side * atan2(lift, absf(anchor.x)))
		run.web.transform = Transform3D(turn, anchor - turn * anchor) * run.home
	for mount in ribbon_forks:
		mount.fork.position = mount.home + Vector3.UP * lift

func _shift(shifted: bool, delta: float) -> void:
	if shift_depth == float(shifted): return
	shift_depth = move_toward(shift_depth, float(shifted), delta * 42.0)
	_offset_pivot(&"HildaShiftBasket", Vector3.DOWN * shift_depth * 0.026)
	_rotate_pivot(&"HildaLeftShift", shift_depth * 0.07)
	_rotate_pivot(&"HildaRightShift", shift_depth * 0.07)
	linkage.sync_basket()

func _process(delta: float) -> void:
	if not model or not writer:
		return
	if support_travel != float(support_setting):
		var contact_before := clampf(support_travel, 0.8, 1.0)
		support_travel = move_toward(support_travel, float(support_setting), delta * 3.0)
		_pose_support()
		if contact_before != clampf(support_travel, 0.8, 1.0):
			_shape_sheet(writer.dimensions(), paper_shape.z)
	if pivots.has(&"HildaRibbonCover") and cover_depth != float(cover_open):
		cover_depth = move_toward(cover_depth, float(cover_open), delta * 3.5)
		var rotation_at_hinge := Basis(Vector3.RIGHT, -0.92 * smoothstep(0.0, 1.0, cover_depth))
		pivots[&"HildaRibbonCover"].transform = rest[&"HildaRibbonCover"] * Transform3D(rotation_at_hinge, cover_hinge - rotation_at_hinge * cover_hinge)
	if queue.is_empty():
		_shift(shift_held or bool(writer.data.get("locked", false)), delta)
		return
	var remaining := delta
	while not queue.is_empty():
		var stroke: Dictionary = queue[0]
		var event: Dictionary = stroke.event
		var service := stroke.has("to_col")
		var duration := float(event.motion_duration) if service else clampf(float(event.get("motion_duration", 0.105)), 0.055, 0.2)
		var step := minf(remaining, duration - elapsed)
		elapsed += step
		remaining -= step
		var phase := minf(elapsed / duration, 1.0)
		var label := str(event.key)
		if service:
			var progress := smoothstep(0.0, 1.0, phase)
			var feed := progress
			if TAB_PARTS.has(label):
				var depression := smoothstep(0.0, 0.2, phase) * (1.0 - smoothstep(0.79, 1.0, phase))
				_tab_pose(label, depression)
				# The rack runs free until the selected stop catches the carriage.
				progress = smoothstep(0.17, 0.86, phase)
			elif label == "return":
				# The lever indexes the paper first, then pushes the carriage
				# into the left stop. Its spring restores the handle on release.
				var swing := lerpf(stroke.preload, 1.0, smoothstep(0.0, 0.25, phase)) * (1.0-smoothstep(0.77,1.0,phase))
				_set_return(swing)
				feed = smoothstep(0.04, 0.31, phase)
				progress = smoothstep(0.14, 0.86, phase)
			_feed_pose(lerpf(stroke.half, stroke.to_half, feed), lerpf(stroke.platen, stroke.to_platen, feed))
			_place_column(lerpf(event.col, stroke.to_col, progress))
			if phase < 1.0: break
			elapsed = 0.0
			queue.pop_front()
			continue
		_feed_pose(stroke.half, stroke.platen)
		var ink := str(event.get("ink", "Black"))
		_shift(bool(event.get("shift", false)), step)
		if phase >= CONTACT_PHASE and not stroke.made_contact:
			# A long display frame can cross contact and rebound together. The
			# callback must still see the selected slug at its printing position.
			_pose(label, 1.0, 1.0, ink)
			_place_column(float(event.col))
			_contact(stroke)
		var depth := smoothstep(0.0, CONTACT_PHASE, phase) if phase < CONTACT_PHASE else 1.0 - smoothstep(CONTACT_PHASE, 0.93, phase)
		var bar := pow(depth, 1.5) if phase < CONTACT_PHASE else pow(depth, 2)
		_pose(label, depth, bar, ink)
		var next_column := float(queue[1].event.col) if queue.size() > 1 else float(writer.data.col)
		_place_column(lerpf(float(event.col), next_column, smoothstep(CONTACT_PHASE, 0.88, phase)))
		if phase < 1.0:
			break
		elapsed = 0.0
		queue.pop_front()
	if queue.is_empty():
		_shift(shift_held or bool(writer.data.get("locked", false)), remaining)
		sync()

func _pick(pointer: Vector2, include_handles: bool) -> Dictionary:
	var at := pointer * Vector2(view.size) / size.max(Vector2.ONE)
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var nearest := INF
	var picked := {}
	var domains := [caps, control_meshes] if include_handles else [caps]
	for domain in domains:
		for label in domain:
			var meshes: Array = domain[label] if domain[label] is Array else [domain[label]]
			for mesh: MeshInstance3D in meshes:
				if not mesh.is_visible_in_tree(): continue
				var local := mesh.global_transform.affine_inverse()
				var local_origin := local * origin
				var local_dir := local.basis * direction
				var hit = mesh.get_aabb().grow(0.003).intersects_ray(local_origin, local_dir)
				if hit == null: continue
				# The long, swept handle and curved selector enclose empty space
				# in their bounding boxes, particularly in the carriage close-up.
				if handle_faces.has(mesh):
					hit = null
					var closest := INF
					var faces:PackedVector3Array = handle_faces[mesh]
					for i in range(0,faces.size(),3):
						var contact = Geometry3D.ray_intersects_triangle(local_origin,local_dir,faces[i],faces[i+1],faces[i+2])
						if contact == null: continue
						var depth := local_origin.distance_squared_to(Vector3(contact))
						if depth < closest:
							hit = contact
							closest = depth
					if hit == null: continue
				var world_hit: Vector3 = mesh.global_transform * Vector3(hit)
				var distance_squared := origin.distance_squared_to(world_hit)
				if distance_squared < nearest:
					nearest = distance_squared
					picked = {"label":label, "point":world_hit}
	return picked

func _hit_key(pointer: Vector2) -> String:
	return str(_pick(pointer, false).get("label", ""))

func _screen_direction(point:Vector3, delta:Vector3) -> Vector2:
	return (camera.unproject_position(point+delta)-camera.unproject_position(point))*size/Vector2(view.size).max(Vector2.ONE)

func _pull_registration():
	flush()
	registration_pulled = true
	if left_knob: left_knob.position = knob_home + Vector3.LEFT*0.065

func release_registration():
	if registration_pulled:
		registration_pulled = false
		handle_grab = ""
		if left_knob: left_knob.position = knob_home

func _begin_handle(label:String, position:Vector2, hit:Vector3, pull:=false) -> void:
	handle_grab = label
	grab_start = position
	grab_start_feed = float(writer.data.platen_half)
	grab_start_detent = spacing_detent()
	grab_moved = false
	pull_axis = _screen_direction(hit,Vector3.LEFT*0.065).normalized() if label=="Left knob" else Vector2.ZERO
	if label=="Left knob" and pull: _pull_registration()
	var step := Vector2.UP*12.0
	if label.ends_with("knob") and pivots.has(&"HildaPlatenRoll"):
		var radial:Vector3 = hit - pivots[&"HildaPlatenRoll"].global_position
		radial.x = 0.0
		var tangent := Vector3.LEFT.cross(radial).normalized()
		step = _screen_direction(hit,tangent*0.5*float(writer.LEADING)*COLUMN_PITCH/float(writer.PITCH))
	elif label == "Return":
		step = _screen_direction(hit,Vector3.RIGHT*0.30)
	elif label == "Spacing":
		step = _screen_direction(hit,Vector3.FORWARD*0.12)
	grab_axis = step.normalized() if step.length_squared()>0.03 else Vector2.UP
	grab_travel_px = maxf(4.0,step.length())

func _drag_handle(position:Vector2) -> void:
	var offset := position-grab_start
	if not grab_moved and offset.length()<4.0: return
	if handle_grab=="Left knob" and not registration_pulled and not grab_moved:
		var outward := offset.dot(pull_axis)
		if outward >= 4.0 and outward > absf(offset.dot(grab_axis))*1.25:
			_pull_registration()
			grab_start = position
			grab_moved = true
			return
	grab_moved = true
	var amount := offset.dot(grab_axis)/grab_travel_px
	match handle_grab:
		"Left knob", "Right knob":
			var initial := grab_start_feed
			var target := initial + (amount if registration_pulled or writer.data.free_platen else roundf(amount))
			var difference := target-float(writer.data.platen_half)
			if absf(difference)>0.0001: carriage_control_requested.emit("register" if registration_pulled else "platen",difference)
		"Spacing":
			var wanted := clampi(grab_start_detent+roundi(amount),0,3)
			if wanted!=spacing_detent(): carriage_control_requested.emit("spacing",float(wanted))
		"Return":
			return_preload = clampf(amount,0.0,1.0)*0.62
			if queue.is_empty(): _set_return(return_preload)

func _end_handle(cancel:bool, reverse:bool=false) -> void:
	var label := handle_grab
	if registration_pulled:
		if cancel:
			carriage_control_requested.emit("register",grab_start_feed-float(writer.data.platen_half))
		release_registration()
		return
	handle_grab = ""
	if label.is_empty(): return
	var direction := -1.0 if reverse else 1.0
	if cancel:
		if label.ends_with("knob") and grab_moved:
			var difference := grab_start_feed-float(writer.data.platen_half)
			if not is_zero_approx(difference): carriage_control_requested.emit("platen",difference)
		elif label=="Spacing" and grab_start_detent!=spacing_detent():
			carriage_control_requested.emit("spacing", float(grab_start_detent))
	elif label=="Return":
		if not grab_moved or return_preload>0.12: carriage_control_requested.emit("return",1.0)
	elif not grab_moved:
		if label=="Spacing": carriage_control_requested.emit("spacing",float(posmod(spacing_detent()+int(direction),4)))
		elif label.ends_with("knob"): carriage_control_requested.emit("platen",direction)
	return_preload = 0.0
	if queue.is_empty(): _set_return(0.0)

func _get_tooltip(at_position:Vector2) -> String:
	if not model: return ""
	var label:String = _pick(at_position,true).get("label","")
	match label:
		"tab": return "Tab · advance to the next stop"
		"tab_clear": return "Clear the tab stop at this column"
		"tab_set": return "Set a tab stop at this column"
		"Return": return "Carriage return · click or pull right and release"
		"Spacing": return "Line spacing · click to cycle, or drag toward the rear to release"
		"Left knob": return "Drag to turn. Pull outward first, or Ctrl-drag, to adjust the baseline. Release to lock; right-click to undo."
		"Right knob": return "Platen knob · drag to roll paper, click to advance, Shift-click to reverse"
	return ""

func _gui_input(event: InputEvent) -> void:
	if not model:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					var picked := _pick(event.position,true)
					var label:String = picked.get("label","")
					if TAB_PARTS.has(label):
						tab_held = label
						_tab_pose(tab_playing, tab_depth)
						carriage_control_requested.emit(label, 1.0)
						accept_event()
					elif control_meshes.has(label):
						_begin_handle(label,event.position,picked.point,event.ctrl_pressed)
						accept_event()
					elif not label.is_empty():
						printing_key_pressed.emit(label, event.shift_pressed)
						if label == "H": key_pressed.emit(event.shift_pressed)
						accept_event()
				elif not tab_held.is_empty():
					tab_held = ""
					_tab_pose(tab_playing, tab_depth)
					accept_event()
				elif not handle_grab.is_empty():
					_end_handle(false,event.shift_pressed)
					accept_event()
			MOUSE_BUTTON_RIGHT:
				if not handle_grab.is_empty():
					if event.pressed: _end_handle(true)
				else: orbiting = event.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11), 2.2, 11.0)
					_frame()
					accept_event()
	elif event is InputEventMouseMotion and not handle_grab.is_empty():
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT)==0: _end_handle(true)
		else: _drag_handle(event.position)
		accept_event()
	elif event is InputEventMouseMotion and orbiting:
		if not (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			orbiting = false
			return
		yaw -= event.relative.x * 0.008
		elevation = clampf(elevation + event.relative.y * 0.007, 0.09, 1.42)
		_frame()
		accept_event()
