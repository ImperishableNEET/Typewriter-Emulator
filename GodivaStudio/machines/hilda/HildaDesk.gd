extends Control

const Shelf = preload("res://machines/MachineShelf.gd")
const Writer = preload("res://Writer.gd")
const PANGRAM := "The quick brown fox jumps over the lazy dog."
const LINE_SPACING := [1.0, 1.5, 2.0, 0.0]
@export var machine_profile:Resource
var writer
var machine
var paper = preload("res://Paper.gd").new()
var reading_line = preload("res://ReadingLine.gd").new()
var page_title := Label.new()
var status := Label.new()
var stack_action:Button
var previous:Button
var next:Button
var draft:Button
var viewed_page := -1
var save_timer := Timer.new()
var demo_timer := Timer.new()
var demo_button:Button
var demo_index := -1
var strike_audio
var spacing_control := OptionButton.new()
var tabs_control := MenuButton.new()

func _ready():
	writer = Writer.new(machine_profile.load_manifest(), machine_profile)
	if not writer.load_file(machine_profile.autosave_path):
		writer.load_file(machine_profile.autosave_path + ".bak")
	Shelf.collect_pages(writer)
	var bg := ColorRect.new()
	bg.color = Color("#202b2c")
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var padding := MarginContainer.new()
	add_child(padding)
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		padding.add_theme_constant_override("margin_" + side, 18)
	var main := VBoxContainer.new()
	padding.add_child(main)
	main.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	main.add_child(header)
	header.add_theme_constant_override("separation", 16)
	heading(header, machine_profile.nickname, 40)
	heading(header, machine_profile.model, 17)
	Shelf.selector(header, machine_profile.id, switch_machine)
	main.add_child(HSeparator.new())
	var panels := HSplitContainer.new()
	panels.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(panels)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for pane in [left, right]:
		panels.add_child(pane)
		pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.7
	var tools := HBoxContainer.new()
	left.add_child(tools)
	var title := heading(tools, "Operator’s view", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var views := MenuButton.new()
	tools.add_child(views)
	views.text = "View ▾"
	views.focus_mode = Control.FOCUS_NONE
	for view_name in ["Operator’s view", "Carriage close-up", "Rear view"]:
		views.get_popup().add_item(view_name)
	views.get_popup().id_pressed.connect(func(index):
		machine.set_carriage_view(false)
		machine.set_rear_view(index==2)
		if index==1: machine.set_carriage_view(true)
		title.text = views.get_popup().get_item_text(index))
	var support := OptionButton.new()
	support.focus_mode = Control.FOCUS_NONE
	for caption in ["Rest folded", "Rest raised", "Rest extended"]:
		support.add_item(caption)
	support.tooltip_text = "Fold, raise or extend the rear paper support"
	support.item_selected.connect(func(index): machine.set_paper_support(index))
	var cover := Button.new()
	tools.add_child(cover)
	cover.text = "Open cover"
	cover.toggle_mode = true
	cover.focus_mode = Control.FOCUS_NONE
	cover.toggled.connect(func(open):
		machine.set_cover_open(open)
		cover.text = "Close cover" if open else "Open cover")
	machine = machine_profile.rig_script.new()
	left.add_child(machine)
	machine.size_flags_vertical = Control.SIZE_EXPAND_FILL
	machine.setup(writer)
	machine.printing_key_pressed.connect(press_cap)
	machine.carriage_control_requested.connect(operate_carriage)
	strike_audio = preload("res://machines/hilda/HildaAudio.gd").new()
	add_child(strike_audio)
	strike_audio.setup(machine)
	right.add_child(page_title)
	page_title.add_theme_font_size_override("font_size", 22)
	right.add_child(paper)
	paper.writer = writer
	paper.clip_contents = true
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var nav := HFlowContainer.new()
	right.add_child(nav)
	stack_action = button(nav, "Stack sheet", stack_sheet)
	previous = button(nav, "Stack", func():browse(writer.data.finished_pages.size()-1 if viewed_page<0 else viewed_page-1))
	next = button(nav, "Next ›", func():browse(viewed_page+1))
	draft = button(nav, "Back to draft", func():browse(-1))
	right.add_child(reading_line)
	reading_line.writer = writer
	reading_line.custom_minimum_size.y = 64
	var footer := HFlowContainer.new()
	main.add_child(footer)
	footer.add_child(support)
	var layout := CheckButton.new()
	footer.add_child(layout)
	layout.text = "Olympia layout"
	layout.focus_mode = Control.FOCUS_NONE
	layout.button_pressed = writer.data.physical
	layout.tooltip_text = "Use the photographed key positions. With this off, type the character shown on your computer keyboard."
	layout.toggled.connect(func(enabled):
		writer.data.physical=enabled
		save_timer.start())
	button(footer, "Key guide", show_key_guide)
	demo_button = button(footer, "Type pangram", toggle_pangram)
	demo_button.tooltip_text = "Type the quick brown fox sentence on the mounted sheet"
	add_child(demo_timer)
	demo_timer.one_shot = true
	demo_timer.timeout.connect(type_demo_character)
	var ribbon := OptionButton.new()
	footer.add_child(ribbon)
	ribbon.focus_mode = Control.FOCUS_NONE
	for color in machine_profile.ribbon_modes: ribbon.add_item(color + " ribbon")
	ribbon.select(machine_profile.ribbon_modes.find(writer.data.ribbon))
	ribbon.item_selected.connect(func(index):
		writer.data.ribbon = machine_profile.ribbon_modes[index]
		refresh()
		save_timer.start())
	footer.add_child(spacing_control)
	spacing_control.focus_mode = Control.FOCUS_NONE
	spacing_control.tooltip_text = "Line-spacing selector on the left carriage end"
	for label in ["Single spacing", "1½ spacing", "Double spacing", "Free platen"]:
		spacing_control.add_item(label)
	spacing_control.item_selected.connect(func(index): operate_carriage("spacing", index))
	footer.add_child(tabs_control)
	tabs_control.text = "Tab stops ▾"
	tabs_control.focus_mode = Control.FOCUS_NONE
	var tab_menu := tabs_control.get_popup()
	tab_menu.add_item("Advance to next stop   (Tab)")
	tab_menu.add_item("Set stop here   (Ctrl+=)")
	tab_menu.add_item("Clear stop here   (Ctrl+−)")
	tab_menu.add_item("Clear all stops   (Ctrl+.)")
	tab_menu.id_pressed.connect(func(index):
		operate_carriage(["tab", "tab_set", "tab_clear", "tab_clear_all"][index], 1.0))
	footer.add_child(status)
	add_child(save_timer)
	save_timer.one_shot = true
	save_timer.wait_time = 0.45
	save_timer.timeout.connect(save_draft)
	if not writer.data.sheet_loaded and not writer.data.finished_pages.is_empty():
		browse(writer.data.finished_pages.size()-1)
	refresh()

func heading(parent:Control, caption:String, points:int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.text = caption
	label.add_theme_font_size_override("font_size", points)
	return label

func button(parent:Control, caption:String, action:Callable) -> Button:
	var control := Button.new()
	parent.add_child(control)
	control.text = caption
	control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(action)
	return control

func _unhandled_key_input(event:InputEvent):
	if not event is InputEventKey: return
	var code:int = event.physical_keycode if event.physical_keycode else event.keycode
	var tab_action := ""
	if not (event.alt_pressed or event.meta_pressed):
		if event.ctrl_pressed:
			if code in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]: tab_action = "tab_set"
			elif code in [KEY_MINUS, KEY_KP_SUBTRACT]: tab_action = "tab_clear"
			elif code == KEY_PERIOD and not event.shift_pressed: tab_action = "tab_clear_all"
		elif code == KEY_TAB and not event.shift_pressed:
			tab_action = "tab"
	if not tab_action.is_empty():
		if event.pressed and not event.echo: operate_carriage(tab_action, 1.0)
		get_viewport().set_input_as_handled()
		return
	if event.alt_pressed and not (event.ctrl_pressed or event.meta_pressed or event.shift_pressed) and event.keycode in [KEY_UP,KEY_DOWN]:
		if event.pressed: operate_carriage("platen",-1.0 if event.keycode==KEY_UP else 1.0)
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		var shortcuts:Dictionary = machine_profile.keyboard.SHORTCUTS
		if event.ctrl_pressed and event.alt_pressed and event.shift_pressed and not event.meta_pressed and shortcuts.has(event.keycode):
			if event.pressed and not event.echo:
				stop_demo()
				type_character(shortcuts[event.keycode])
			get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_SHIFT:
		machine.set_shift(event.shift_pressed if not event.pressed else true)
		return
	if not event.pressed or event.echo: return
	if not writer.data.physical and event.unicode>=32:
		var character := String.chr(event.unicode)
		if writer.mappings.has(character) or character==" ":
			stop_demo()
			type_character(character)
			get_viewport().set_input_as_handled()
		return
	if not writer.data.physical: code = event.keycode
	if not writer.data.physical and not event.shift_pressed and code in [KEY_1, KEY_KP_1]:
		stop_demo()
		type_character("1")
		get_viewport().set_input_as_handled()
		return
	var printable:String = machine_profile.keyboard.physical_pair(code)
	if not printable.is_empty():
		press_cap(printable,event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	var chars := {KEY_SPACE:" ", KEY_BACKSPACE:"\b", KEY_ENTER:"\n", KEY_KP_ENTER:"\n"}
	if chars.has(event.keycode):
		stop_demo()
		type_character(chars[event.keycode])
		get_viewport().set_input_as_handled()

func press_cap(key:String, shifted:bool):
	stop_demo()
	if key == "Space":
		type_character(" ")
		return
	var faces:Array = machine_profile.keyboard.faces_for(key)
	if faces.size()==2: type_character(faces[int(shifted)], shifted and faces[0]==faces[1])

func show_key_guide():
	var guide := AcceptDialog.new()
	add_child(guide)
	guide.title = "Hilda’s printing keyboard"
	guide.dialog_text = machine_profile.operator_notes
	guide.confirmed.connect(guide.queue_free)
	guide.canceled.connect(guide.queue_free)
	guide.popup_centered()

func stop_demo():
	demo_index = -1
	demo_timer.stop()
	demo_button.text = "Type pangram"

func toggle_pangram():
	if demo_index >= 0:
		stop_demo()
		return
	if viewed_page >= 0 or not writer.data.sheet_loaded: return
	demo_index = 0
	demo_button.text = "Stop typing"
	type_demo_character()

func type_demo_character():
	if demo_index < 0: return
	if demo_index >= PANGRAM.length() or viewed_page >= 0 or not writer.data.sheet_loaded:
		stop_demo()
		return
	# Return before a word that would cross the right margin.
	if demo_index == 0 or PANGRAM[demo_index-1] == " ":
		var word_length := PANGRAM.substr(demo_index).get_slice(" ",0).length()
		if writer.data.col + word_length - 1 > writer.data.right:
			type_character("\n")
			if writer.message != "":
				stop_demo()
				return
	var glyph := PANGRAM[demo_index]
	if glyph == " " and writer.data.col > writer.data.right: type_character("\n")
	else: type_character(glyph)
	if not writer.message.is_empty():
		stop_demo()
		return
	demo_index += 1
	if demo_index == PANGRAM.length():
		stop_demo()
	else:
		demo_timer.start(clampf(writer.paste_interval(glyph,PANGRAM[demo_index],5.5),0.11,0.4))

func type_character(character:String, duplicate_face_shift:=false):
	if viewed_page >= 0 or not writer.data.sheet_loaded or machine.registration_pulled: return
	var prior_column:int = writer.data.col
	var prior_half:float = writer.data.half
	var prior_platen:float = writer.data.platen_half
	var event = writer.action(character, Time.get_ticks_msec(), true, false, -1., true)
	if event.is_empty():
		if character == " " and writer.data.col != prior_column:
			machine.space_advance(prior_column)
		elif character == "\n" and writer.message.is_empty():
			machine.carriage_motion("return",prior_column,prior_half,prior_platen)
		elif character == "\t" and writer.message.is_empty():
			machine.carriage_motion("tab",prior_column,prior_half,prior_platen)
		refresh()
	else:
		# Both faces on the comma and period slugs print the same character.
		if duplicate_face_shift: event.shift = true
		machine.strike(event, func():
			if writer.owns_event(event) and not event.miss and not event.jam: strike_audio.play_strike(event)
			writer.deposit(event)
			refresh())
	save_timer.start()

func operate_carriage(control:String,value:float):
	if viewed_page >= 0: return
	if machine.registration_pulled and control!="register": return
	stop_demo()
	writer.message=""
	match control:
		"tab":
			type_character("\t")
			return
		"tab_set", "tab_clear":
			if control == "tab_set": writer.set_tab_here()
			else: writer.clear_tab_here()
			machine.carriage_motion(control, writer.data.col, writer.data.half, writer.data.platen_half)
			var verb := "set" if control == "tab_set" else "cleared"
			writer.message = "Tab %s at column %d" % [verb, writer.data.col + 1]
		"tab_clear_all":
			writer.clear_all_tabs()
			writer.message = "All tab stops cleared"
		"return":
			type_character("\n")
			return
		"spacing":
			var index := int(value)
			if index < 0 or index >= LINE_SPACING.size(): return
			writer.data.spacing = LINE_SPACING[index]
			writer.data.free_platen = index==3
		"platen":
			var before:float = writer.data.half
			var before_platen:float = writer.data.platen_half
			writer.turn(value)
			machine.carriage_motion("platen",writer.data.col,before,before_platen)
		"register":
			if not machine.registration_pulled: return
			writer.PaperGrab.turn(writer,value,false)
		_: return
	refresh()
	save_timer.start()

func refresh():
	machine.sync()
	paper.queue_redraw()
	reading_line.queue_redraw()
	var count:int = writer.data.finished_pages.size()
	var reading := viewed_page >= 0
	spacing_control.disabled = reading
	tabs_control.disabled = reading
	spacing_control.select(3 if writer.data.free_platen else maxi(0,LINE_SPACING.find(float(writer.data.spacing))))
	page_title.text = ("%s · Sheet %d of %d" % [str(writer.data.finished_pages[viewed_page].get("machine_id","godiva")).capitalize(), viewed_page+1, count]) if reading else ("Mounted sheet" if writer.data.sheet_loaded else "Empty platen")
	reading_line.visible = not reading and writer.data.sheet_loaded
	if demo_button: demo_button.disabled = reading or not writer.data.sheet_loaded
	previous.text = "‹ Previous" if reading else "Stack (%d)" % count
	previous.disabled = count == 0 or viewed_page == 0
	next.visible = reading
	next.disabled = viewed_page >= count-1
	draft.visible = reading and writer.data.sheet_loaded
	stack_action.text = "Stack sheet" if writer.data.sheet_loaded else "Load sheet"
	stack_action.visible = not reading or not writer.data.sheet_loaded
	status.text = writer.message if writer.message else "Line %s   Column %d" % [str(snappedf(1.+float(writer.data.half)/2.,0.01)), writer.data.col+1]

func browse(index:int):
	if index < -1 or index >= writer.data.finished_pages.size(): return
	stop_demo()
	viewed_page = index
	paper.show_finished(writer.finished_image(index) if index >= 0 else null)
	refresh()

func stack_sheet():
	machine.flush()
	if writer.data.sheet_loaded:
		if writer.finish_page(): browse(writer.data.finished_pages.size()-1)
	else:
		writer.new_stock("Letter")
		browse(-1)
	save_draft()

func save_draft():
	if not writer.save_file(machine_profile.autosave_path): status.text = "Could not save Hilda’s draft"

func switch_machine(target:String):
	machine.flush()
	if Shelf.switch_to(self, writer, target) != OK: status.text = "Could not save the draft or open the selected machine"

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and machine:
		machine.flush()
		save_draft()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and machine:
		machine.set_shift(false)
		machine.release_registration()
