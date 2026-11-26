extends SceneTree
## Exercise physical keyboard events on either production desk, using an isolated draft.

const FIRST := 16
const SECOND := 34
var desk
var machine_id := ""
var errors := PackedStringArray()

func _initialize():
	call_deferred("run")

func check(ok: bool, description: String):
	if not ok:
		errors.append(description)
		push_error("%s: %s" % [machine_id, description])

func key(code: Key, unicode_value := 0, ctrl := false, shifted := false):
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.ctrl_pressed = ctrl
	event.shift_pressed = shifted
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	# Advance the actual contact and release callbacks between operator actions.
	if machine_id == "hilda":
		desk.machine.flush()
	else:
		desk.machine._process(0.5)

func word(value: String, expected_column: int, expected_half: int):
	var writer = desk.writer
	var start: int = writer.data.events.size()
	for letter in value:
		var unicode_value := letter.unicode_at(0)
		key(letter.to_upper().unicode_at(0) as Key, unicode_value, false, letter != letter.to_lower())
	var events: Array = writer.data.events.slice(start)
	check(events.size() == value.length(), "Typed all of '%s'" % value)
	for index in mini(value.length(), events.size()):
		var strike: Dictionary = events[index]
		check(strike.glyph == value[index] and strike.col == expected_column + index
			and is_equal_approx(strike.half, expected_half) and not strike.jam and not strike.miss,
			"Expected '%s' on line %d at column %d" % [value[index], 1 + expected_half / 2, expected_column + index + 1])

func field(value: String, expected_column: int, expected_half: int):
	var column := expected_column
	for token in value.split(" "):
		if column > expected_column:
			key(KEY_SPACE, 32)
			column += 1
		word(token, column, expected_half)
		column += token.length()

func has_ink(column: int, half: int) -> bool:
	var writer = desk.writer
	var x_start: int = writer.MARGIN + column * writer.PITCH
	var y_start: int = roundi(writer.BASE + half * writer.LEADING / 2.0 - 1.125 * writer.PITCH)
	var sheet: Image = writer.raster
	var paper_color := sheet.get_pixel(0, 0)
	for y in range(y_start, y_start + writer.PITCH):
		for x in range(x_start, x_start + writer.PITCH):
			if sheet.get_pixel(x, y) != paper_color:
				return true
	return false

func run():
	machine_id = OS.get_environment("TAB_PROOF_MACHINE")
	if OS.get_environment("HILDA_QA") != "isolated" or machine_id not in ["godiva", "hilda"]:
		quit(2)
		return
	var scene_path := "res://Desk.tscn" if machine_id == "godiva" else "res://machines/hilda/HildaDesk.tscn"
	change_scene_to_file(scene_path)
	await process_frame
	await process_frame
	desk = current_scene
	desk.writer.reset()
	desk.writer.data.seed = 3009
	key(KEY_PERIOD, 0, true)
	check(desk.writer.data.tabs.is_empty(), "Clear the factory stops with the master clear control")
	for step in FIRST: key(KEY_SPACE, 32)
	key(KEY_EQUAL, 0, true)
	for step in SECOND - FIRST: key(KEY_SPACE, 32)
	key(KEY_EQUAL, 0, true)
	check(desk.writer.data.tabs.size() == 2 and FIRST in desk.writer.data.tabs
		and SECOND in desk.writer.data.tabs, "Set stops at displayed columns 17 and 35")
	key(KEY_ENTER)
	var rows := [
		["Machine", "Model", "Origin"],
		["Hilda", "SM9 De Luxe", "Germany"],
		["Godiva", "Hermes 3000", "Switzerland"],
	]
	for index in rows.size():
		var row: Array = rows[index]
		field(row[0], 0, 2 + index * 2)
		key(KEY_TAB)
		field(row[1], FIRST, 2 + index * 2)
		key(KEY_TAB)
		field(row[2], SECOND, 2 + index * 2)
		key(KEY_ENTER)
	key(KEY_TAB)
	key(KEY_MINUS, 0, true)
	check(desk.writer.data.tabs == [SECOND], "Clear only the first stop")
	for step in FIRST: key(KEY_BACKSPACE)
	field("Stop cleared", 0, 8)
	key(KEY_TAB)
	field("Lands here", SECOND, 8)
	check(desk.writer.pending_ink.is_empty(), "Every strike has reached the mounted sheet")
	for half in [2, 4, 6]:
		check(has_ink(0, half) and has_ink(FIRST, half) and has_ink(SECOND, half),
			"All three aligned words left ink on the mounted sheet")
	check(has_ink(0, 8) and not has_ink(FIRST, 8) and has_ink(SECOND, 8),
		"Final mounted row has ink at the origin and remaining stop, with a blank at the cleared stop")
	var path := OS.get_environment("TAB_PROOF_IMAGE")
	if errors.is_empty() and not path.is_empty():
		# Crop the app's normal high-resolution paper export to the four typed lines.
		var proof: Image = desk.writer.export_image(false, 2).get_region(Rect2i(46, 118, 1410, 254))
		check(proof.save_png(path) == OK, "Save the typed sheet crop")
	if errors.is_empty():
		print("TAB_STOPS_OK ", machine_id, " columns=1,17,35 cleared=17 next=35")
	quit(0 if errors.is_empty() else 1)
