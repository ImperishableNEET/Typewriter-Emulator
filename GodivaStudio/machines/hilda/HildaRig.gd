extends SubViewportContainer
## Operator viewport for Hilda's articulated GLB. Writer owns the strike and
## sheet state. The escapement steps after the slug touches the ribbon.
signal key_pressed(shifted: bool)
signal printing_key_pressed(key: String, shifted: bool)

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
	&"HildaLeftShift", &"HildaRightShift"]

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
var cover_hinge := Vector3.ZERO
var shift_held := false
var shift_depth := 0.0
var yaw := 0.22
var elevation := 0.48
var distance := 7.45
var rear_view := false
var rear_fill:DirectionalLight3D
var orbiting := false

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
	sync()

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
	var aspect := maxf(size.x / maxf(size.y, 1.0), 0.5)
	var fit := maxf(1.0, 1.28 / aspect)
	camera.position = target + distance * fit * Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation))
	camera.look_at(target)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(camera) and camera.is_inside_tree():
		_frame()

func set_rear_view(enabled: bool) -> void:
	rear_view = enabled
	yaw = PI if enabled else 0.22
	elevation = 0.14 if enabled else 0.48
	distance = 6.5 if enabled else 7.45
	rear_fill.light_energy = 0.42 if enabled else 0.075
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
	return PLATEN_CENTER + Vector3(x, tail * 0.96, -PAPER_RADIUS - tail * 0.28)

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

func sync() -> void:
	if not model or not writer:
		return
	sheet.visible = bool(writer.data.get("sheet_loaded", true))
	if last_texture != writer.texture:
		last_texture = writer.texture
		sheet_material.set_shader_parameter("page", last_texture)
	var dims: Vector2i = writer.dimensions()
	var shape := Vector3(dims.x, dims.y, float(writer.data.half))
	if shape != paper_shape:
		paper_shape = shape
		_shape_sheet(dims, shape.z)
	if queue.is_empty():
		_place_column(float(writer.data.col))

func strike(event: Dictionary, on_contact: Callable) -> void:
	if event.is_empty():
		return
	queue.append({"event": event, "callback": on_contact, "made_contact": false})
	if queue.size() == 1:
		elapsed = 0.0
		_place_column(float(event.col))

func space_advance(from_column: int) -> void:
	# Spaces use the escapement but do not lift the ribbon or strike the page.
	strike({"key":"Space", "col":from_column, "shift":shift_held,
		"motion_duration":0.085}, Callable())

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
		var duration := clampf(float(event.get("motion_duration", 0.105)), 0.055, 0.2)
		var step := minf(remaining, duration - elapsed)
		elapsed += step
		remaining -= step
		var phase := minf(elapsed / duration, 1.0)
		var label := str(event.key)
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

func _hit_key(pointer: Vector2) -> String:
	var at := pointer * Vector2(view.size) / size.max(Vector2.ONE)
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var nearest := INF
	var selected := ""
	for label in caps:
		var mesh: MeshInstance3D = caps[label]
		if not mesh.is_visible_in_tree():
			continue
		var local := mesh.global_transform.affine_inverse()
		var hit = mesh.get_aabb().grow(0.003).intersects_ray(local * origin, local.basis * direction)
		if hit == null: continue
		var distance_squared := origin.distance_squared_to(mesh.global_transform * Vector3(hit))
		if distance_squared < nearest:
			nearest = distance_squared
			selected = label
	return selected

func _gui_input(event: InputEvent) -> void:
	if not model:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					var label := _hit_key(event.position)
					if not label.is_empty():
						printing_key_pressed.emit(label, event.shift_pressed)
						if label == "H": key_pressed.emit(event.shift_pressed)
						accept_event()
			MOUSE_BUTTON_RIGHT:
				orbiting = event.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11), 2.2, 11.0)
					_frame()
					accept_event()
	elif event is InputEventMouseMotion and orbiting:
		if not (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			orbiting = false
			return
		yaw -= event.relative.x * 0.008
		elevation = clampf(elevation + event.relative.y * 0.007, 0.09, 1.42)
		_frame()
		accept_event()
