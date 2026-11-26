extends VBoxContainer

const LEVELS=["light","medium-light","medium-firm","firm"]
var reader
var config:ConfigFile
var controls:Window
var calibrate:=Button.new()
var reset_curve:=Button.new()
var feedback:=Label.new()
var active:=false
var points:Array=[]
var start_ms:=0.
var config_path:="user://wooting.cfg"

func setup(touch,preferences:ConfigFile,window:Window):
	reader=touch
	config=preferences
	controls=window
	var buttons=HBoxContainer.new()
	add_child(buttons)
	for b in [calibrate,reset_curve]:
		buttons.add_child(b)
		b.focus_mode=Control.FOCUS_NONE
	add_child(feedback)
	feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	calibrate.pressed.connect(toggle_capture)
	reset_curve.text="Restore default touch"
	reset_curve.pressed.connect(func():save_curve([]))
	controls.visibility_changed.connect(func():
		if not controls.visible and active:finish("Calibration cancelled."))
	refresh()

func refresh():
	calibrate.text="Cancel calibration" if active else "Calibrate touch…"
	calibrate.disabled=not reader.connected and not active
	calibrate.tooltip_text="Enable Wooting analog touch and connect a compatible keyboard."
	reset_curve.visible=not active and not reader.anchors.is_empty()
	feedback.visible=not feedback.text.is_empty()

func toggle_capture():
	if active:
		finish("Calibration cancelled.")
	elif reader.connected:
		reader.poll()
		reader.samples.clear()
		start_ms=Time.get_unix_time_from_system()*1000.
		active=true
		points.clear()
		prompt()
	refresh()

func prompt():
	feedback.text="Stroke %d of 4 · Tap and release lowercase L with a %s touch." % [points.size()+1,LEVELS[points.size()]]

func finish(message:String):
	active=false
	points.clear()
	reader.samples.clear()
	feedback.text=message
	refresh()

func save_curve(curve:Array):
	var previous=reader.anchors
	config.set_value("input","curve",curve)
	if config.save(config_path)!=OK:
		config.set_value("input","curve",previous)
		finish("Couldn’t save the touch profile. Your previous setting is still active.")
		return
	reader.anchors=curve.duplicate()
	finish("Default touch restored." if curve.is_empty() else "Personal touch saved. Return to writing to try it.")

func _process(_delta):
	if not controls or not controls.visible:return
	if active and not reader.connected:
		finish("Keyboard disconnected. Reconnect to calibrate.")
	if active:
		# The reader emits one sample per measured downstroke. OS key repeat,
		# regular keyboards and the writing sheet never enter this capture path.
		var batch=reader.samples.duplicate()
		reader.samples.clear()
		for sample in batch:
			if sample[0]!=reader.hid_for(KEY_L) or sample[1]<start_ms:continue
			points.append(sample[2])
			if points.size()<4:
				prompt()
			elif reader.valid_curve(points):
				save_curve(points.duplicate())
				break
			else:
				finish("The four strokes were too similar or out of order. Try again, getting firmer with each L.")
				break
	refresh()
