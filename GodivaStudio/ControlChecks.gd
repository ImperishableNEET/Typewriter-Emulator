extends RefCounted

# Drive the actual shortcut and 3D picking paths, including key release and repeat.
static func ctrl_key(desk, code:int, shifted:=false, alt:=false):
	var key=InputEventKey.new()
	key.keycode=code
	key.physical_keycode=code
	key.ctrl_pressed=true
	key.shift_pressed=shifted
	key.alt_pressed=alt
	key.pressed=true
	desk._input(key)
	key.echo=true
	desk._input(key)
	key.echo=false
	key.pressed=false
	desk._input(key)

static func click_cap(desk, cap:String):
	var machine=desk.machine
	desk.check(machine.keys.has(cap),"exported picking target for "+cap)
	if not machine.keys.has(cap):return
	var event=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	event.position=machine.camera.unproject_position(machine.vec(machine.keys[cap]))
	machine._gui_input(event)
	event.pressed=false
	machine._gui_input(event)

static func run(desk):
	var w=desk.writer
	for physical in [false,true]:
		w.reset()
		w.data.physical=physical
		for position in [3,0,2,1]:
			var ribbon=w.data.ribbon
			var col=w.data.col
			var strikes=w.data.events.size()
			ctrl_key(desk,KEY_1+position,true,true)
			desk.check(w.data.touch_regulator==position,"touch shortcut selects position %d" % (position+1))
			desk.check(w.data.ribbon==ribbon and w.data.col==col and w.data.events.size()==strikes,"touch selection leaves ribbon and page alone")
		var colors=["Black","Red","Split","Stencil"]
		# Change away from the first selection before exercising Ctrl+1.
		desk.ribbon_button.item_selected.emit(1)
		desk.check(w.data.ribbon=="Red","ribbon dropdown changes the writer")
		for index in colors.size():
			var count:int=w.data.events.size()
			var col:int=w.data.col
			ctrl_key(desk,KEY_1+index)
			desk.check(w.data.ribbon==colors[index] and desk.ribbon_button.selected==index,"ribbon hotkey and selector agree for "+colors[index])
			desk.check(w.data.events.size()==count and w.data.col==col,"selector has no strike or escapement motion")
			desk.type_char("x")
			desk.check(w.data.events.back().ink==colors[index],"next strike uses "+colors[index])

		for key in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
			var step=-1 if key==KEY_BRACKETLEFT else 1
			var ribbon_pos=float(w.data.ribbon_pos)
			var count:int=w.data.events.size()
			ctrl_key(desk,key)
			ctrl_key(desk,key)
			desk.check(w.data.direction==step and is_equal_approx(w.data.ribbon_pos,ribbon_pos) and w.data.events.size()==count,"manual direction selects one spool and does not feed ink")
			desk.type_char("x")
			desk.check(signf(w.data.ribbon_pos-ribbon_pos)==step,"next strike advances toward selected spool")

		# A manual choice at the eyelet still leaves automatic reversal operable.
		w.data.ribbon_pos=5999.9999
		ctrl_key(desk,KEY_BRACKETRIGHT)
		desk.type_char("x")
		desk.check(is_equal_approx(w.data.ribbon_pos,6000) and w.data.direction==-1,"right eyelet reverses after manual right take-up")
		desk.type_char("x")
		desk.check(w.data.ribbon_pos<6000,"strike after the eyelet feeds away from the right end")
		w.data.ribbon_pos=.0001
		ctrl_key(desk,KEY_BRACKETLEFT)
		desk.type_char("x")
		desk.check(is_zero_approx(w.data.ribbon_pos) and w.data.direction==1,"left eyelet reverses after manual left take-up")
		desk.type_char("x")
		desk.check(w.data.ribbon_pos>0,"strike after the eyelet feeds away from the left end")
		for index in colors.size():
			var swatch=["Blue","Red","Yellow","Stencil"][index]
			click_cap(desk,"Ribbon index "+swatch)
			desk.check(w.data.ribbon==colors[index],"picking "+swatch+" selects "+colors[index])
		desk.machine.set_cut(true)
		for side in ["left","right"]:
			click_cap(desk,"Ribbon guide "+side)
			desk.check(w.data.direction==(-1 if side=="left" else 1),"picking the "+side+" ribbon guide selects its spool")
		desk.machine.set_cut(false)
		w.data.tabs=[7,19]
		w.move_col(13)
		var before_count:int=w.data.events.size()
		var shift=InputEventKey.new()
		shift.keycode=KEY_SHIFT
		shift.physical_keycode=KEY_SHIFT
		shift.ctrl_pressed=true
		shift.pressed=true
		desk._input(shift)
		ctrl_key(desk,KEY_EQUAL,true)
		shift.pressed=false
		desk._input(shift)
		ctrl_key(desk,KEY_EQUAL)
		desk.check(w.data.tabs.size()==3 and 13 in w.data.tabs,"Ctrl+Shift+= and Ctrl+= set a single stop")
		desk.check(not w.data.locked,"typing the Ctrl+plus chord leaves Shift Lock alone")
		ctrl_key(desk,KEY_MINUS)
		desk.check(w.data.tabs==[7,19] and w.data.col==13,"Ctrl+minus clears only the current tab")
		click_cap(desk,"+")
		desk.check(13 in w.data.tabs,"picking the plus cap sets a stop")
		click_cap(desk,"−")
		desk.check(w.data.tabs==[7,19],"picking the minus cap clears one stop")
		ctrl_key(desk,KEY_PERIOD)
		desk.check(w.data.tabs.is_empty() and w.data.col==13,"Ctrl+period sweeps the bank without moving the carriage")
		click_cap(desk,"+")
		w.move_col(3)
		click_cap(desk,"TAB")
		desk.check(w.data.col==13,"TAB catches the stop set with the mouse")
		click_cap(desk,"···")
		desk.check(w.data.tabs.is_empty() and w.data.col==13,"picking the three-dot cap clears the bank")
		desk.check(w.data.events.size()==before_count,"tab controls leave existing impressions intact")

		ctrl_key(desk,KEY_3)
		ctrl_key(desk,KEY_BRACKETLEFT)
		ctrl_key(desk,KEY_EQUAL)
		var path=OS.get_environment("TEMP").path_join("godiva-player-tools").path_join("control-shortcuts.godiva")
		var saved_position:float=w.data.ribbon_pos
		desk.check(w.save_file(path),"save sheet with custom tab and ribbon settings")
		w.reset()
		desk.check(w.load_file(path),"load sheet with custom tab and ribbon settings")
		desk.check(w.data.tabs==[13] and w.data.direction==-1 and w.data.ribbon=="Split" and is_equal_approx(w.data.ribbon_pos,saved_position),"sheet preserves tab, ribbon setting, position and direction")
		ctrl_key(desk,KEY_MINUS)
		desk.check(w.data.tabs.is_empty(),"clear a stop restored from disk")
	w.reset()
	desk.sync()
