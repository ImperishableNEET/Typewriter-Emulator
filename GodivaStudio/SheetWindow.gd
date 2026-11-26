extends Window
## Hosts the existing paper and writing line so both windows share one document.
var desk
var dock
var padding:MarginContainer

func setup(host, panel:Control):
	desk=host
	dock=panel.get_parent()
	title="Typewriter Emulator • "+desk.machine_profile.nickname+" — The sheet"
	visible=false
	force_native=true
	min_size=Vector2i(320,260)
	theme=desk.theme
	desk.add_child(self)
	var bg=ColorRect.new()
	bg.color=Color(desk.BG)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding=MarginContainer.new()
	bg.add_child(padding)
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:
		padding.add_theme_constant_override("margin_"+edge,12)
	var main:Window=desk.get_window()
	var usable=DisplayServer.screen_get_usable_rect(main.current_screen)
	size=Vector2i(Vector2(panel.size)+Vector2(24,24)).clamp(min_size,usable.size.max(min_size))
	position=(main.position+Vector2i(main.size.x-size.x+30,54)).clamp(usable.position,(usable.end-size).max(usable.position))
	close_requested.connect(desk.dock_sheet)
	window_input.connect(forward_key)
	focus_exited.connect(release_inputs)

func open(panel:Control):
	panel.reparent(padding,false)
	show()
	grab_focus()

func close_to_dock(panel:Control):
	release_inputs()
	panel.reparent(dock,false)
	hide()
	desk.get_window().grab_focus()

func forward_key(event:InputEvent):
	if event is InputEventKey:
		if desk.settings.visible or desk.prompt.visible or desk.file_dialog.visible:return
		desk.get_viewport().push_input(event,true)
		set_input_as_handled()

func release_inputs():
	if not is_instance_valid(desk.machine):return
	desk.lock_chord_pending=false
	desk.shift_tap_location=-1
	desk.release_margin_key()
	desk.machine.shift_inputs=Vector2.ZERO
	desk.machine.shift_pulse=Vector2.ZERO
	desk.machine.release_carriage_controls()
