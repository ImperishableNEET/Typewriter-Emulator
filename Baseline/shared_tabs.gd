extends SceneTree
## Exercise the same tab bank against the two machines' actual paper and type.
const Writer = preload("res://Writer.gd")
const PROFILES = [
	preload("res://machines/godiva/Godiva.tres"),
	preload("res://machines/hilda/Hilda.tres"),
]

var failed := false

func _initialize():
	for profile in PROFILES:
		check_machine(profile)
	if not failed:
		print("SHARED_TABS_OK")
	quit(1 if failed else 0)

func check_condition(profile, condition:bool, reason:String):
	if not condition:
		failed = true
		push_error("%s: %s" % [profile.nickname, reason])

func check_machine(profile):
	var writer = Writer.new(profile.load_manifest(), profile)
	writer.clear_all_tabs()
	# Set them from right to left, and try to set the first one twice.
	for column in [27, 12, 12]:
		writer.move_col(column)
		writer.set_tab_here()
	check_condition(profile, writer.data.tabs == [27, 12], "two distinct stops")
	writer.move_col(0)
	var clock := 1000
	for character in "a\tb\tc\nd\te\tf\n":
		writer.action(character, clock)
		clock += 180
	writer.action("\t", clock)
	writer.clear_tab_here()
	writer.move_col(0)
	writer.action("g", clock + 180)
	writer.action("\t", clock + 360)
	writer.action("h", clock + 540)
	var positions := []
	for strike in writer.data.events:
		positions.append(Vector2i(strike.col, strike.half))
	check_condition(profile, positions == [
		Vector2i(0, 0), Vector2i(12, 0), Vector2i(27, 0),
		Vector2i(0, 2), Vector2i(12, 2), Vector2i(27, 2),
		Vector2i(0, 4), Vector2i(27, 4)
	], "two aligned rows and third row skipping the cleared stop")
	writer.data.right = 19
	writer.move_col(12)
	writer.action("\t", clock)
	check_condition(profile, writer.data.col == 19, "margin arrests the carriage before a stop")
	writer.set_margin_held(true)
	writer.action("\t", clock)
	check_condition(profile, writer.data.col == 27, "margin release allows reaching the stop")
	writer.set_margin_held(false)
	writer.clear_all_tabs()
	writer.action("\t", clock)
	check_condition(profile, writer.data.col == writer.rail_right(), "released margin and empty bank reach the rail")
	writer.move_col(0)
	writer.action("\t", clock)
	check_condition(profile, writer.data.col == 19, "empty bank catches the right margin")
	writer.move_col(28)
	writer.action("\t", clock)
	check_condition(profile, writer.data.col == 28, "tab never pulls the carriage backwards")
