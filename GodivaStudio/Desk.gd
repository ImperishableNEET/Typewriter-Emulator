extends Control
const Writer=preload("res://Writer.gd")
const MachineProfile=preload("res://machines/MachineProfile.gd")
@export var machine_profile:MachineProfile
const Paper=preload("res://Paper.gd")
const Publish=preload("res://Publish.gd")
const Wooting=preload("res://WootingTouch.gd")
var wooting=Wooting.new()
var wooting_status:Label
const BG="#182922"
const SURFACE="#263a30"
const LINE="#46594c"
const FG="#f3ead7"
const SOFT="#b0c1af"
const ACCENT="#d3b789"
var writer
var machine
var reading_line
var paper
var left:VBoxContainer
var right:VBoxContainer
var status:Label
var info:Label
var ribbon_button:OptionButton
var page_title:Label
var viewed_page:=-1
var stack_action:Button
var previous_page:Button
var next_page:Button
var draft_button:Button
var line_title:Label
var sheet_window
var pop_sheet_button:Button
var dock_sheet_button:Button
var view_button:Button
var cut_button:Button
var replay_button:Button
var queue_button:Button
var settings:Window
var file_dialog:FileDialog
var factory_prompt:ConfirmationDialog
var prompt:ConfirmationDialog
var file_task=""
var mechanism_audio = preload("res://MechanismAudio.gd").new()
var paste_text=""
var paste_tick=0.
var paused=false
var pace=7.
var save_tick=-1.
var note_time=0.
var note=""
var shift_mouse=false
var lock_chord_pending=false
var shift_tap_location=-1
var active_margin_key=KEY_NONE
var focus_paper=false
var recording=false
var frames=[]
var replay_token=0
var test_failures=[]
var shortcut_keys={"Cutaway":KEY_F2,"Replay":KEY_F3,"Page view":KEY_F4}
var rebinding=""
var record_tick=0.
var record_path=""
var save_path=""
var test_mode=false
var prefs={}
var slider_labels={}
var margin_left:SpinBox
var margin_right:SpinBox
var pending_sheet="Letter"
var toolbar:HBoxContainer
var font_serif=SystemFont.new()
var font_ui=SystemFont.new()
func _ready():
	test_mode="--self-test" in OS.get_cmdline_user_args() or "--screenshot" in OS.get_cmdline_user_args()
	font_serif.font_names=PackedStringArray(["Georgia","Times New Roman"]);font_ui.font_names=PackedStringArray(["Segoe UI","Arial"])
	var theme_local=Theme.new();theme_local.default_font=font_ui;theme_local.default_font_size=15;theme=theme_local
	writer=Writer.new(machine_profile.load_manifest(),machine_profile)
	if not test_mode and not writer.load_file(machine_profile.autosave_path):writer.load_file(machine_profile.autosave_path+".bak")
	if not test_mode:preload("res://machines/MachineShelf.gd").collect_pages(writer)
	var config=ConfigFile.new()
	if config.load("user://keys.cfg")==OK:
		for label in shortcut_keys:shortcut_keys[label]=config.get_value("keys",label,shortcut_keys[label])
	build_ui();build_settings();build_dialogs();build_audio();machine.setup_grabs(self);sync()
	if not writer.data.sheet_loaded and not writer.data.finished_pages.is_empty():browse_page(writer.data.finished_pages.size()-1)
	get_window().min_size=Vector2i(960,650)
	if test_mode:call_deferred("run_test")
	elif "--draft-check-write" in OS.get_cmdline_user_args() or "--draft-check-read" in OS.get_cmdline_user_args():call_deferred("draft_check")
func style(col:String,border:String="",radius:=5)->StyleBoxFlat:
	var v=StyleBoxFlat.new();v.bg_color=Color(col);v.set_corner_radius_all(radius)
	if border!="":v.border_color=Color(border);v.set_border_width_all(1)
	v.content_margin_left=12;v.content_margin_right=12;v.content_margin_top=7;v.content_margin_bottom=7
	return v
func lbl(parent,txt:String,pt:=15,color:=FG,serif:=false)->Label:
	var l=Label.new();parent.add_child(l);l.text=txt;l.add_theme_font_size_override("font_size",pt);l.add_theme_color_override("font_color",Color(color))
	if serif:l.add_theme_font_override("font",font_serif)
	l.mouse_filter=Control.MOUSE_FILTER_IGNORE;return l
func btn(parent,txt:String,fn:Callable,tip:="")->Button:
	var b=Button.new();parent.add_child(b);b.text=txt;b.tooltip_text=tip;b.focus_mode=Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal",style(SURFACE,LINE));b.add_theme_stylebox_override("hover",style("#3d5446",SOFT));b.add_theme_stylebox_override("pressed",style("#486653"));b.pressed.connect(fn);return b
func opt(parent,labels:Array,fn:Callable)->OptionButton:
	var b=OptionButton.new();parent.add_child(b);b.focus_mode=Control.FOCUS_NONE
	for l in labels:b.add_item(l)
	b.add_theme_stylebox_override("normal",style(SURFACE,LINE));b.item_selected.connect(fn);return b
func space(parent):
	var c=Control.new();c.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(c)
func row(parent,sep=8)->HBoxContainer:
	var r=HBoxContainer.new();r.add_theme_constant_override("separation",sep);parent.add_child(r);return r
func build_ui():
	var bg=ColorRect.new();bg.color=Color(BG);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(bg)
	var pad=MarginContainer.new();add_child(pad);pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:pad.add_theme_constant_override("margin_"+edge,22 if edge in ["left","right"] else 14)
	var main=VBoxContainer.new();pad.add_child(main);main.add_theme_constant_override("separation",10)
	var mast=row(main,14);lbl(mast,machine_profile.nickname,43,FG,true);lbl(mast,machine_profile.model.to_upper(),14,SOFT)
	preload("res://machines/MachineShelf.gd").selector(mast,machine_profile.id,switch_machine)
	space(mast);btn(mast,"New sheet",func():confirm_sheet("Letter"));btn(mast,"Open…",func():dialog("Open"));btn(mast,"Save as…",func():dialog("Save"));btn(mast,"Export…",show_export);btn(mast,"Machine controls",show_settings)
	var rule=HSeparator.new();main.add_child(rule)
	var deck=row(main,18);deck.size_flags_vertical=Control.SIZE_EXPAND_FILL
	left=VBoxContainer.new();deck.add_child(left);left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=1.6
	right=VBoxContainer.new();deck.add_child(right);right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.size_flags_stretch_ratio=1.
	var lh=row(left);lbl(lh,"Operator’s view",24,FG,true);space(lh);cut_button=btn(lh,"Cutaway",toggle_cut,"F2 • expose the typebars");replay_button=btn(lh,"Replay strike",replay_last,"F3 • replay the latest strike")
	dock_sheet_button=btn(lh,"Dock sheet",dock_sheet,"Return the separate sheet to the writing room")
	dock_sheet_button.hide()
	build_machine_view()
	var ph=row(right);page_title=lbl(ph,"The sheet",24,FG,true);space(ph);view_button=btn(ph,"Enlarge",toggle_focus,"F4 • enlarge the page")
	pop_sheet_button=btn(ph,"Pop out",toggle_sheet_window,"Open the sheet in a separate, resizable window")
	paper=Paper.new();paper.clip_contents=true;right.add_child(paper);paper.writer=writer;paper.size_flags_vertical=Control.SIZE_EXPAND_FILL;paper.picked.connect(replay_event)
	var pages=HFlowContainer.new();right.add_child(pages)
	stack_action=btn(pages,"Stack sheet",func():
		if writer.data.sheet_loaded:finish_page()
		else:load_next_sheet())
	previous_page=btn(pages,"‹ Previous",func():browse_page(viewed_page-1 if viewed_page>=0 else writer.data.finished_pages.size()-1))
	next_page=btn(pages,"Next ›",func():browse_page(viewed_page+1))
	draft_button=btn(pages,"Back to draft",func():browse_page(-1))
	line_title=lbl(right,"Writing line",17,SOFT,true)
	reading_line=preload("res://ReadingLine.gd").new();reading_line.writer=writer;right.add_child(reading_line);reading_line.custom_minimum_size.y=67
	toolbar=row(main,8);lbl(toolbar,"RIBBON",12,SOFT);ribbon_button=opt(toolbar,machine_profile.ribbon_modes,set_ribbon)
	var ribbon_keys=PackedStringArray()
	for i in machine_profile.ribbon_modes.size():
		ribbon_keys.append("Ctrl+%d %s"%[i+1,machine_profile.ribbon_modes[i]])
	ribbon_button.tooltip_text="   ".join(ribbon_keys)
	btn(toolbar,"↵  Return",func():type_char("\n"));btn(toolbar,"½ line ↑",func():roll_page(-1));btn(toolbar,"½ line ↓",func():roll_page(1))
	btn(toolbar,"Margin release",tap_margin_release,"\\ or | • pass the margin or clear jammed typebars");space(toolbar);queue_button=btn(toolbar,"Paste & type",paste_or_pause,"Ctrl+V • check the clipboard, then type it")
	var foot=row(main);status=lbl(foot,"",14,SOFT);space(foot);info=lbl(foot,"",14,ACCENT)
func build_audio():
	mechanism_audio.sound_directory=machine_profile.sound_directory
	add_child(mechanism_audio)
	mechanism_audio.bind_machine(machine)
func sound(tag:String,power:=1.,take:int=-1,tempo:="",trim_db:=0.,source_key:=""):
	mechanism_audio.play_action(tag,writer.data.volume,power,take,tempo,trim_db,source_key)

func sound_platen(touch:float=-1.):
	var drive=writer.service_profile("platen",Time.get_ticks_msec(),touch)
	sound("platen",drive.gain,-1,drive.sound_tempo)

var shift_take=-1
var shift_gain=.8
var shift_tempo="normal"

func sound_shift_press(source:String,drive:Dictionary={}):
	if drive.is_empty():
		var fraction=machine.key_grabs.shift_strength()
		if fraction<0. and source!="Shift lock" and wooting.connected:
			var speed=wooting.take_speed(229 if source=="Right shift" else 225,Time.get_unix_time_from_system()*1000.)
			if speed>0.:fraction=wooting.touch_fraction(speed)
		drive=writer.service_profile("shift",Time.get_ticks_msec(),fraction)
	shift_take=mechanism_audio.select_take("shift_press")
	shift_gain=float(drive.get("gain",1.))*.8
	shift_tempo=drive.get("sound_tempo","normal")
	sound("shift_press",shift_gain,shift_take,shift_tempo,0.,source)

func sound_shift_release(source:String,speed:float,excursion:float):
	# A hand easing the basket home softens its upper-stop contact. A free
	# spring return keeps the tempo and performance variation of the press.
	var free_return=clampf(speed/22.,0.,1.)
	var tempo="deliberate" if free_return<.45 else shift_tempo
	var gain=shift_gain*lerpf(.34,1.,sqrt(free_return))*sqrt(excursion)
	sound("shift_release",gain,shift_take,tempo,0.,source)
	shift_take=-1
	shift_gain=.8
	shift_tempo="normal"

func sound_carriage_return(columns:int,hand_speed:float=-1.,drive:Dictionary={}):
	var distance=absi(columns)
	if drive.is_empty():
		var fraction=clampf(inverse_lerp(.25,2.5,hand_speed),0.,1.) if hand_speed>=0. else -1.
		drive=writer.service_profile("return",Time.get_ticks_msec(),fraction)
	machine.return_duration=clampf(drive.motion_duration*3.5,.17,.68)
	var gain=drive.gain*lerpf(.72,1.,clampf(distance/48.,0.,1.))
	sound("return_short" if distance<=8 else "return",gain,-1,drive.sound_tempo)

func sound_stroke(stroke:Dictionary):
	var tag="jam" if stroke.jam else ("miss" if stroke.miss else "strike")
	var gain=maxf(.3,stroke.power)*.7 if stroke.jam else (maxf(.2,stroke.power)*.75 if stroke.miss else stroke.power)
	var take:int=int(stroke.get("sound_take",-1))
	if take<0 or take>=mechanism_audio.bank[tag].size():
		take=mechanism_audio.select_take(tag)
		stroke.sound_take=take
	sound(tag,gain,take,stroke.get("sound_tempo",""))
func build_machine_view():
	machine=machine_profile.rig_script.new()
	left.add_child(machine)
	machine.size_flags_vertical=Control.SIZE_EXPAND_FILL
	machine.setup(writer)
	machine.operated.connect(physical_click)
	machine.carriage_changed.connect(changed)

func switch_machine(target:String):
	for index in writer.pending_ink.keys():writer.deposit(writer.data.events[index])
	if preload("res://machines/MachineShelf.gd").switch_to(self,writer,target)!=OK:
		notice("Could not save the draft or open the selected machine")

func reset_machine_keep_sheet():
	machine.release_carriage_controls()
	settings.hide()
	var index=machine.get_index()
	var camera_pose=[machine.cut,machine.yaw,machine.tilt,machine.zoom,machine.inspection.offset]
	machine.active=false
	left.remove_child(machine)
	machine.queue_free()
	writer.reset_mechanism()
	shift_mouse=false
	lock_chord_pending=false
	shift_tap_location=-1
	active_margin_key=KEY_NONE
	replay_token+=1
	reading_line.sample=null
	wooting.samples.clear()
	paused=not paste_text.is_empty()
	build_machine_view()
	left.move_child(machine,index)
	machine.setup_grabs(self)
	mechanism_audio.bind_machine(machine)
	machine.set_cut(camera_pose[0])
	machine.yaw=camera_pose[1];machine.tilt=camera_pose[2];machine.zoom=camera_pose[3];machine.inspection.offset=camera_pose[4]
	machine.update_camera()
	changed()
	notice("Machine reset • sheet and writing position kept")

func build_dialogs():
	file_dialog=FileDialog.new();add_child(file_dialog);file_dialog.access=FileDialog.ACCESS_FILESYSTEM;file_dialog.use_native_dialog=true
	file_dialog.file_selected.connect(file_chosen)
	prompt=ConfirmationDialog.new();add_child(prompt);prompt.title="Load a fresh sheet";prompt.ok_button_text="Load sheet"
	prompt.confirmed.connect(func():load_next_sheet(pending_sheet))

func finish_page()->bool:
	if not writer.finish_page():return false
	replay_token+=1
	reading_line.sample=null
	paste_text=""
	browse_page(writer.data.finished_pages.size()-1)
	changed()
	notice("Sheet placed on the stack")
	return true

func load_next_sheet(stock:String=""):
	if writer.data.sheet_loaded and not writer.data.events.is_empty():
		if not writer.finish_page():return
	if stock.is_empty():stock=writer.data.paper
	writer.new_stock(stock)
	paste_text=""
	paper.carbon=false
	browse_page(-1)
	changed()
	notice("Fresh "+stock.to_lower()+" loaded")

func browse_page(index:int):
	var count:int=writer.data.finished_pages.size()
	if index < -1 or index>=count:return
	viewed_page=index
	if index>=0 and not paste_text.is_empty():paused=true
	paper.show_finished(writer.finished_image(index,paper.carbon) if index>=0 else null)
	sync()

func output_image()->Image:
	if viewed_page>=0:return writer.finished_image(viewed_page,paper.carbon)
	return writer.export_image(paper.carbon)

func confirm_sheet(stock:String):
	machine.release_carriage_controls()
	pending_sheet=stock
	if writer.data.events.is_empty():prompt.confirmed.emit();return
	prompt.dialog_text="Place the current sheet on the finished stack and load a fresh "+stock.to_lower()+"?";prompt.popup_centered()
func dialog(task:String):
	machine.release_carriage_controls()
	file_task=task
	file_dialog.current_dir=OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS);file_dialog.title=task
	file_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE if task=="Open" else FileDialog.FILE_MODE_SAVE_FILE
	var ext={"Open":machine_profile.document_extension,"Save":machine_profile.document_extension,"Export PNG":"png","Print PDF":"pdf","Record GIF":"gif"}[task]
	file_dialog.filters=PackedStringArray(["*."+ext+" ; "+task])
	file_dialog.current_file="" if task=="Open" else (machine_profile.nickname+" - "+Time.get_date_string_from_system()+"."+ext)
	file_dialog.popup_centered_ratio(.73)
func file_chosen(path:String):
	var ok=false
	match file_task:
		"Open":
			ok=writer.load_file(path)
			if ok:
				save_path=path;paste_text="";paper.carbon=false
				browse_page(-1 if writer.data.sheet_loaded else writer.data.finished_pages.size()-1)
				changed()
		"Save":
			if path.get_extension().to_lower()!=machine_profile.document_extension:path+="."+machine_profile.document_extension
			ok=writer.save_file(path)
			if ok:save_path=path
		"Export PNG":
			if path.get_extension().to_lower()!="png":path+=".png"
			ok=output_image().save_png(path)==OK
		"Print PDF":
			if path.get_extension().to_lower()!="pdf":path+=".pdf"
			var stock=writer.data.finished_pages[viewed_page].paper if viewed_page>=0 else writer.data.paper
			ok=Publish.pdf(path,output_image(),stock=="Postcard")
		"Record GIF":
			if path.get_extension().to_lower()!="gif":path+=".gif"
			record_path=path;frames.clear();record_tick=0;recording=true;notice("Recording the writing room for five seconds");return
	notice(("Opened " if file_task=="Open" else "Saved ")+path.get_file() if ok else "Could not "+file_task.to_lower()+" this file")
func show_export():
	var popup=PopupMenu.new();add_child(popup)
	for item in ["Export PNG","Print PDF","Record GIF"]:popup.add_item(item)
	popup.id_pressed.connect(func(i):dialog(["Export PNG","Print PDF","Record GIF"][i]))
	popup.popup_hide.connect(popup.queue_free);popup.position=Vector2i(get_viewport().get_mouse_position());popup.popup()
func show_settings():
	machine.release_carriage_controls()
	margin_left.min_value=writer.rail_left()+1;margin_right.min_value=writer.rail_left()+2
	margin_left.max_value=writer.rail_right();margin_right.max_value=writer.rail_right()+1
	margin_left.set_value_no_signal(writer.data.left+1);margin_right.set_value_no_signal(writer.data.right+1)
	for key in prefs:
		var widget=prefs[key]
		if widget is CheckButton:widget.set_pressed_no_signal(bool(writer.data[key]))
		elif widget is Slider:
			widget.set_value_no_signal(writer.data[key]);slider_labels[key].text=str(roundi(float(writer.data[key])*100))+"%"
		elif key=="spacing":widget.select(int(writer.data.spacing)-1)
	for panel in machine.bottom_panels.LABELS:
		prefs[panel].disabled=machine.cut
		prefs[panel].set_pressed_no_signal(not machine.cut and writer.data[panel])
		prefs[panel].tooltip_text="Cutaway has removed both panels." if machine.cut else "Fit or remove this panel."
	var available=Vector2i(get_viewport_rect().size)-Vector2i(32,64)
	var preferred=settings.size if settings.has_meta("opened") else Vector2i(710,600)
	settings.popup_centered(preferred.min(available).max(settings.min_size))
	settings.set_meta("opened",true)
func toggle_setting(parent,key,text):
	var c=CheckButton.new();parent.add_child(c);c.text=text;c.button_pressed=bool(writer.data[key]);prefs[key]=c
	c.toggled.connect(func(v):
		writer.data[key]=float(v) if key=="support_lift" else v
		if key=="bail_up":writer.data.bail_lift=float(v)
		changed())
func slider(parent,key,text):
	var line=row(parent);var name_label=lbl(line,text,15);name_label.custom_minimum_size.x=162
	var s=HSlider.new();line.add_child(s);s.size_flags_horizontal=Control.SIZE_EXPAND_FILL;s.max_value=1;s.step=.01;s.value=writer.data[key];prefs[key]=s
	var num=lbl(line,"",14,SOFT);num.custom_minimum_size.x=46;slider_labels[key]=num
	s.value_changed.connect(func(v):
		if key=="bail_left":v=minf(v,writer.data.bail_right-.19/2.44)
		if key=="bail_right":v=maxf(v,writer.data.bail_left+.19/2.44)
		s.set_value_no_signal(v)
		writer.data[key]=v;num.text=str(roundi(v*100))+"%";changed())
func settings_page(tabs:TabContainer,title:String)->VBoxContainer:
	var scroll=ScrollContainer.new()
	scroll.name=title
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	tabs.add_child(scroll)
	var pad=MarginContainer.new()
	scroll.add_child(pad)
	pad.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for edge in ["left","right","top","bottom"]:pad.add_theme_constant_override("margin_"+edge,14)
	var box=VBoxContainer.new()
	pad.add_child(box)
	box.add_theme_constant_override("separation",10)
	return box

func settings_flow(parent)->HFlowContainer:
	var flow=HFlowContainer.new()
	parent.add_child(flow)
	flow.add_theme_constant_override("h_separation",10)
	flow.add_theme_constant_override("v_separation",6)
	return flow

func build_settings():
	settings=Window.new();settings.title="Typewriter Emulator • Machine controls";settings.transient=true;settings.exclusive=true;settings.visible=false;add_child(settings)
	settings.min_size=Vector2i(320,300)
	settings.close_requested.connect(settings.hide)
	var back=ColorRect.new();back.color=Color(BG);settings.add_child(back);back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout=VBoxContainer.new();back.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left=12;layout.offset_top=10;layout.offset_right=-12;layout.offset_bottom=-10
	layout.add_theme_constant_override("separation",9)
	var tabs=TabContainer.new();layout.add_child(tabs)
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	tabs.use_hidden_tabs_for_min_size=false
	tabs.add_theme_stylebox_override("panel",style(BG,LINE))
	tabs.add_theme_stylebox_override("tab_selected",style(SURFACE,LINE))
	var machine_page=settings_page(tabs,"Machine")
	var paper_page=settings_page(tabs,"Paper")
	var sound_page=settings_page(tabs,"Sound")
	var keys_page=settings_page(tabs,"Keys")
	lbl(machine_page,"View & inspection",21,FG,true)
	factory_prompt=ConfirmationDialog.new()
	settings.add_child(factory_prompt)
	factory_prompt.title="Restore factory defaults?"
	factory_prompt.ok_button_text="Restore defaults"
	factory_prompt.dialog_text="Start with blank Letter paper and reset all machine controls, shortcuts, views, and analog calibration. The current sheet will be saved in the app’s Factory reset backups folder. Your saved documents stay in place."
	factory_prompt.confirmed.connect(restore_factory_defaults)
	var camera_row=settings_flow(machine_page)
	toggle_setting(camera_row,"show_floor","Show floor")
	toggle_setting(camera_row,"camera_collision","Camera collision")
	btn(camera_row,"Frame machine",func():machine.frame_machine();settings.hide())
	var underside=settings_flow(machine_page)
	toggle_setting(underside,"base_cover","Bottom cover")
	toggle_setting(underside,"inner_pan","Inner mechanism pan")
	btn(underside,"View underside",func():
		writer.data.show_floor=false
		machine.frame_machine()
		machine.tilt=-PI*.5
		machine.update_camera()
		changed();settings.hide())
	lbl(machine_page,"Typing action",21,FG,true)
	var options=settings_flow(machine_page);toggle_setting(options,"mechanical","Mechanical faults");toggle_setting(options,"physical","Physical layout");toggle_setting(options,"carbon","Carbon copy")
	if OS.get_name()=="Windows":
		var touch_row=settings_flow(machine_page)
		var analog=CheckButton.new();touch_row.add_child(analog);analog.text="Wooting analog touch"
		var config=ConfigFile.new()
		if not test_mode and config.load("user://wooting.cfg")==OK:
			analog.button_pressed=config.get_value("input","enabled",false)
			var stored=config.get_value("input","curve",[])
			if Wooting.valid_curve(stored):wooting.anchors=stored
		if analog.button_pressed:wooting.start()
		wooting_status=lbl(touch_row,wooting.status,14,SOFT)
		var calibration=preload("res://TouchCalibration.gd").new()
		machine_page.add_child(calibration)
		calibration.setup(wooting,config,settings)
		analog.toggled.connect(func(enabled):
			if enabled:wooting.start()
			else:wooting.clean_up()
			config.set_value("input","enabled",enabled)
			config.save("user://wooting.cfg"))
	for a in [["touch","Touch variation"],["alignment","Alignment wear"],["freshness","Ribbon freshness"]]:slider(machine_page,a[0],a[1])
	lbl(sound_page,"Sound levels",21,FG,true)
	for a in [["volume","Master volume"],["keys_volume","Keys and spacebar"],["controls_volume","Carriage and controls"]]:slider(sound_page,a[0],a[1])
	toggle_setting(sound_page,"spatial_audio","3D sound follows the operator’s view")
	lbl(paper_page,"Carriage & paper",21,FG,true)
	var line=settings_flow(paper_page);lbl(line,"Line spacing");prefs.spacing=opt(line,["Single","Double","Triple"],func(i):writer.data.spacing=i+1;changed())
	btn(line,"Reverse ribbon",func():set_ribbon_direction(-int(writer.data.direction)))
	btn(line,"View carbon",func():paper.carbon=not paper.carbon;settings.hide();browse_page(viewed_page))
	var margins=settings_flow(paper_page);lbl(margins,"Margins");margin_left=SpinBox.new();margins.add_child(margin_left);margin_right=SpinBox.new();margins.add_child(margin_right)
	btn(margins,"Set",func():set_margins())
	var car=settings_flow(paper_page);btn(car,"← Move",func():writer.move_col(writer.data.col-1);changed());btn(car,"Move →",func():writer.move_col(writer.data.col+1);changed());btn(car,"Set tab here",func():operate_tab_key("+"))
	btn(car,"Clear tab",func():operate_tab_key("−"))
	var stock=settings_flow(paper_page);btn(stock,"Load letter paper",func():settings.hide();confirm_sheet("Letter"));btn(stock,"Load postcard",func():settings.hide();confirm_sheet("Postcard"))
	toggle_setting(paper_page,"bail_up","Lift the paper bail")
	toggle_setting(paper_page,"support_lift","Extend the paper supports")
	slider(paper_page,"bail_left","Left bail roller");slider(paper_page,"bail_right","Right bail roller")
	lbl(keys_page,"Keyboard & shortcuts",21,FG,true)
	var speed=settings_flow(keys_page);lbl(speed,"Paste speed");var speed_choice=opt(speed,["4 keys / sec","7 keys / sec","12 keys / sec","18 keys / sec"],func(i):pace=[4.,7.,12.,18.][i]);speed_choice.select(1)
	var instructions=lbl(keys_page,machine_profile.operator_notes+"\nRight-click during a drag to cancel it. Double-click a control to restore its default, or a caught bar or linkage to free it. Two clicks on a printing key type twice. Right-drag to orbit, Ctrl+right-drag to pan, and scroll to zoom. Hide the floor for underside views. Turn off camera collision to move through the machine.\nChoose a shortcut button below to assign a function key.",15,SOFT)
	instructions.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var shortcuts=settings_flow(keys_page);lbl(shortcuts,"Shortcuts",15,SOFT)
	for action in shortcut_keys:
		var bind=btn(shortcuts,action+" · "+OS.get_keycode_string(shortcut_keys[action]),func():pass)
		bind.pressed.connect(func():rebinding=action;bind.text="Press F1–F12…";bind.set_meta("capture",true))
		bind.set_meta("binding",action);bind.add_to_group("bindings")
	settings.window_input.connect(func(ev):
		if rebinding!="" and ev is InputEventKey and ev.pressed:
			if ev.keycode!=KEY_ESCAPE and ev.keycode not in shortcut_keys.values() and ev.keycode>=KEY_F1 and ev.keycode<=KEY_F12:
				shortcut_keys[rebinding]=ev.keycode
				var cfg=ConfigFile.new()
				for name in shortcut_keys:cfg.set_value("keys",name,shortcut_keys[name])
				cfg.save("user://keys.cfg")
			rebinding=""
			for b in get_tree().get_nodes_in_group("bindings"):
				var name=b.get_meta("binding");b.text=name+" · "+OS.get_keycode_string(shortcut_keys[name]))
	lbl(machine_page,"Reset machine",21,FG,true)
	var resets=settings_flow(machine_page)
	btn(resets,"Reset and keep sheet",reset_machine_keep_sheet,"Reset the mechanisms and keep your sheet and writing position.")
	btn(resets,"Restore factory defaults…",func():factory_prompt.popup_centered())
	var bottom=row(layout)
	btn(bottom,"Credits",show_credits);space(bottom);btn(bottom,"Back to writing",settings.hide)
	for child in settings.find_children("*","BaseButton",true,false):
		child.focus_mode=Control.FOCUS_ALL
func restore_factory_defaults():
	var root=ProjectSettings.globalize_path("user://Factory reset backups")
	var backup=root.path_join(Time.get_datetime_string_from_system().replace(":","-")+"-"+str(Time.get_ticks_usec()))
	if DirAccess.make_dir_recursive_absolute(backup)!=OK or not writer.save_file(backup.path_join("Current sheet."+machine_profile.document_extension)):
		factory_reset_error("Could not save a recovery copy of the current sheet.")
		return
	# Move the saved preferences as a group. A fresh scene then uses exactly
	# the same startup path and defaults as a new installation.
	var moved:Array[String]=[]
	for name in ["keys.cfg","wooting.cfg",machine_profile.autosave_path.get_file()+".bak",machine_profile.autosave_path.get_file()]:
		var original=ProjectSettings.globalize_path("user://"+name)
		if not FileAccess.file_exists(original):continue
		if DirAccess.rename_absolute(original,backup.path_join(name))!=OK:
			for previous in moved:
				DirAccess.rename_absolute(backup.path_join(previous),ProjectSettings.globalize_path("user://"+previous))
			factory_reset_error("Could not move "+name+" into the recovery folder.")
			return
		moved.append(name)
	save_tick=-1.
	get_tree().reload_current_scene()

func factory_reset_error(message:String):
	var error_box=AcceptDialog.new()
	settings.add_child(error_box)
	error_box.title="Factory reset stopped"
	error_box.dialog_text=message
	error_box.confirmed.connect(error_box.queue_free)
	error_box.canceled.connect(error_box.queue_free)
	error_box.popup_centered()

func show_credits():
	var dialog_box=AcceptDialog.new();settings.add_child(dialog_box);dialog_box.title="About Typewriter Emulator"
	var text=TextEdit.new();text.editable=false;text.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;text.custom_minimum_size=Vector2(470,280)
	text.text="Typewriter Emulator by ImperishableNEET and contributors\nCode: MIT. Published original models and recordings: CC BY 4.0. Credited third-party sound recordings: CC0.\nhttps://github.com/ImperishableNEET/Typewriter-Emulator/blob/main/ASSETS.md\n\n"+machine_profile.credits+"\n\nGodot Engine\n"+Engine.get_license_text()+"\n\n"
	for item in Engine.get_copyright_info():
		text.text+=str(item.name)+"\n"
		for part in item.parts:text.text+="\n".join(part.copyright)+"\n"+str(part.license)+"\n"
	for name in Engine.get_license_info():text.text+="\n"+name+"\n"+Engine.get_license_info()[name]+"\n"
	dialog_box.add_child(text);dialog_box.confirmed.connect(dialog_box.queue_free);dialog_box.canceled.connect(dialog_box.queue_free);dialog_box.popup_centered()
func set_margins():
	if writer.data.center_locked:notice("Release the carriage centering lock first");return
	if margin_left.value>=margin_right.value:notice("Left margin must precede the right margin");return
	writer.data.left=int(margin_left.value)-1;writer.data.right=int(margin_right.value)-1;changed()
func set_margin_here(side:String):
	if writer.set_flying_margin(side):
		changed()
		notice("%s margin set at column %d" % [side.capitalize(),1+int(writer.data[side])])
	else:notice("Choose a printable column before the right margin" if side=="left" else "Choose a printable column after the left margin")
func physical_click(key:String,shifted:bool,hid:=0):
	if key=="Touch regulator":
		change_touch(-1 if shifted else 1)
		return
	if key.begins_with("Flying margin "):
		set_margin_here(key.get_slice(" ",2))
		return
	if key.begins_with("Ribbon index "):
		var index=["Blue","Red","Yellow","Stencil"].find(key.trim_prefix("Ribbon index "))
		if index>=0:set_ribbon(index)
		return
	if key.begins_with("Ribbon guide "):
		set_ribbon_direction(-1 if key.ends_with("left") else 1)
		return
	match key:
		"Left shift","Right shift":
			if writer.data.locked:
				if key!=machine_profile.keyboard.SHIFT_RELEASE_KEY:return
				shift_mouse=false;machine.key_latched=false;toggle_shift_lock()
			else:
				shift_mouse=not shift_mouse;machine.key_latched=shift_mouse;notice("Shift armed" if shift_mouse else "Shift released")
			return
		"Shift lock":
			if not writer.data.locked:toggle_shift_lock()
			return
		"Space","Spacebar":type_char(" ",hid);return
		"⇄":tap_margin_release();return
		"↶":type_char("\b",hid);return
		"+","−","···":operate_tab_key(key,hid);return
		"TAB":type_char("\t",hid);return
	if not writer.meta.bars.has(key):return
	var chars=writer.pair_for(key);type_char(chars[int(shifted or shift_mouse)],hid);shift_mouse=false;machine.key_latched=false
func set_ribbon(index:int):
	if index<0 or index>=machine_profile.ribbon_modes.size():return
	writer.data.ribbon=machine_profile.ribbon_modes[index]
	changed()
	notice("Ribbon • "+machine_profile.ribbon_modes[index])

func set_ribbon_direction(direction:int):
	writer.data.direction=direction
	changed()
	notice("Left spool taking up ribbon" if direction<0 else "Right spool taking up ribbon")

func operate_tab_key(key:String,hid:=0):
	var col=int(writer.data.col)
	match key:
		"+":writer.set_tab_here()
		"−":writer.clear_tab_here()
		"···":writer.clear_all_tabs()
	var fraction=machine.key_grabs.pointer_strength
	if hid!=0 and wooting.connected:
		var speed=wooting.take_speed(hid,Time.get_unix_time_from_system()*1000.)
		if speed>0.:fraction=wooting.touch_fraction(speed)
	var drive=writer.service_profile(key,Time.get_ticks_msec(),fraction)
	drive.key=key
	machine.strike(drive)
	changed()
	match key:
		"+":notice("Tab set at column %d" % (col+1))
		"−":notice("Tab cleared at column %d" % (col+1))
		"···":notice("All tab stops cleared")

func change_touch(delta:int):
	set_touch_position(int(writer.data.touch_regulator)+delta)

func set_touch_position(position:int):
	writer.set_touch_regulator(position)
	changed()
	notice("Touch regulator • %d of 4" % (1+int(writer.data.touch_regulator)))

func machine_shortcut(key:int,event:InputEventKey)->bool:
	var echo=event.echo
	var lighter=event.keycode==KEY_LESS or key==KEY_LESS or (event.shift_pressed and key==KEY_COMMA)
	var heavier=event.keycode==KEY_GREATER or key==KEY_GREATER or (event.shift_pressed and key==KEY_PERIOD)
	if lighter or heavier:
		if not echo:change_touch(-1 if lighter else 1)
		return true
	match key:
		KEY_1,KEY_2,KEY_3,KEY_4:
			if not echo:set_ribbon(key-KEY_1)
		KEY_BRACKETLEFT,KEY_BRACKETRIGHT:
			if not echo:set_ribbon_direction(-1 if key==KEY_BRACKETLEFT else 1)
		KEY_EQUAL,KEY_PLUS,KEY_KP_ADD:
			if not echo:operate_tab_key("+",Wooting.hid_for(key))
		KEY_MINUS,KEY_KP_SUBTRACT:
			if not echo:operate_tab_key("−",Wooting.hid_for(key))
		KEY_PERIOD:
			if not echo:operate_tab_key("···",Wooting.hid_for(key))
		_:return false
	return true

func roll_page(n):
	var previous:float=writer.data.platen_half
	writer.turn(n)
	if previous!=writer.data.platen_half and not writer.data.free_platen:sound_platen()
	changed()
func press_margin_release():
	var was_jammed:bool=writer.data.jammed
	writer.set_margin_held(true)
	if not paste_text.is_empty() and (writer.message.begins_with("Right margin") or was_jammed):paused=false
	changed();notice("Typebars released" if was_jammed else "Margin release")
func tap_margin_release():
	if active_margin_key!=KEY_NONE:return
	press_margin_release()
	writer.set_margin_held(false)
	machine.tap_margin_key()
	changed()
func release_margin_key():
	if active_margin_key==KEY_NONE:return
	active_margin_key=KEY_NONE
	writer.set_margin_held(machine.key_grabs.held=="⇄")
	machine.set_margin_key(false)
	changed()
func type_char(ch:String,hid:=0,pointer_speed:float=-1.,exact_face:=false):
	if viewed_page>=0 or not writer.data.sheet_loaded:
		notice("Return to the draft to type" if writer.data.sheet_loaded else "Load a sheet to type")
		return false
	if not exact_face:ch=machine.key_grabs.shift_character(ch)
	if pointer_speed<0.:pointer_speed=machine.key_grabs.pointer_strength
	if writer.data.center_locked:
		notice("Release the carriage centering lock to type")
		return false
	if writer.carriage_held():
		notice("Let go of the carriage to type")
		return false
	replay_token+=1;reading_line.sample=null
	var analog=hid!=0 and wooting.connected
	var pressed_ms=Time.get_unix_time_from_system()*1000. if analog else 0.
	var service_tag:String={" ":"space","\b":"backspace","\t":"tab","\n":"return"}.get(ch,"")
	var drive={}
	var pending_service_trace=false
	if service_tag!="":
		var fraction=pointer_speed
		if analog:
			var measured=wooting.take_speed(hid,pressed_ms)
			if measured>0.:fraction=wooting.touch_fraction(measured)
			else:pending_service_trace=true
		drive=writer.service_profile(service_tag,Time.get_ticks_msec(),fraction)
		drive.key={"space":"Space","backspace":"↶","tab":"TAB","return":"Carriage return"}[service_tag]
		if ch=="\t":machine.strike(drive)
	var starting_column:int=writer.data.col
	var stroke=writer.action(ch,Time.get_ticks_msec(),not test_mode or analog,analog,pointer_speed,exact_face)
	if not stroke.is_empty():
		if hid!=0:machine.key_grabs.bind_print_hid(hid,stroke.key)
		if analog:match_downstroke(stroke,hid,pressed_ms)
		var this_sheet=writer.raster
		if test_mode or pointer_speed>=0.:
			if pointer_speed<0.:machine.strike(stroke)
			if analog or not test_mode:writer.deposit(stroke)
			sound_stroke(stroke)
		else:machine.strike(stroke,false,func():
			if writer.raster==this_sheet:
				if analog and not stroke.has("downstroke_speed"):match_downstroke(stroke,hid,pressed_ms)
				writer.deposit(stroke);sound_stroke(stroke);sync())
	elif service_tag!="":
		var key_motion=service_tag in ["space","backspace"]
		if writer.message.is_empty():
			var columns=starting_column-int(writer.data.col)
			if service_tag=="return":machine.return_phase=1.
			var this_sheet=writer.raster
			var contact=func():
				if writer.raster!=this_sheet:return
				if pending_service_trace:
					var measured=wooting.take_speed(hid,pressed_ms)
					if measured>0.:writer.refine_profile(drive,wooting.touch_fraction(measured))
				play_service(service_tag,drive,columns)
			if key_motion and pointer_speed<0.:machine.strike(drive,false,contact)
			elif pending_service_trace:get_tree().create_timer(.04).timeout.connect(contact)
			else:contact.call()
		elif key_motion:machine.strike(drive)
	if writer.bell:
		var trigger=drive if stroke.is_empty() else stroke
		sound("bell",clampf(float(trigger.get("gain",1.)),.8,1.1),-1,trigger.get("sound_tempo",""))
	if writer.message!="":notice(writer.message)
	if writer.message.begins_with("Right margin") or writer.message.begins_with("Bottom") or writer.message.begins_with("Paper edge") or writer.data.jammed:paused=true
	paper.follow=true;changed()
	return not stroke.is_empty() or writer.message.is_empty()
func play_service(tag:String,drive:Dictionary,columns:int):
	if tag=="return":sound_carriage_return(columns,-1.,drive)
	else:sound(tag,.75*drive.gain,-1,drive.sound_tempo)

func match_downstroke(stroke:Dictionary,hid:int,pressed_ms:float):
	var speed=wooting.take_speed(hid,pressed_ms)
	if speed>0.:writer.apply_downstroke(stroke,speed,stroke.ribbon_transfer,wooting.touch_fraction(speed))
func paste_or_pause():
	if viewed_page>=0 or not writer.data.sheet_loaded:
		notice("Return to the draft to paste" if writer.data.sheet_loaded else "Load a sheet to paste")
		return
	if not paste_text.is_empty():
		paused=not paused;sync();return
	var txt=writer.expanded(DisplayServer.clipboard_get())
	if txt.is_empty():notice("The clipboard has no text");return
	var bad=writer.unsupported(txt)
	if not bad.is_empty():notice("Paste paused • unavailable characters: "+" ".join(bad.slice(0,12)));return
	paste_text=txt;paused=false;paste_tick=0;sync()
func replay_event(e:Dictionary):
	if focus_paper:toggle_focus()
	if not machine.cut:toggle_cut()
	replay_token+=1;var token=replay_token
	reading_line.show_strike(e,false);machine.strike(e,true,func():
		if token==replay_token:
			reading_line.show_strike(e,true)
			sound_stroke(e))
	get_tree().create_timer(2.6).timeout.connect(func():
		if token==replay_token:reading_line.sample=null;reading_line.queue_redraw())
	notice("Slow replay • "+e.input+"  /  "+e.key+("  /  missed" if e.miss else ("  /  jam" if e.jam else "  /  "+e.ink)))
func replay_last():
	if viewed_page<0 and not writer.data.events.is_empty():replay_event(writer.data.events.back())
func toggle_cut():
	machine.set_cut(not machine.cut);cut_button.text="Close cutaway" if machine.cut else "Cutaway"
func toggle_sheet_window():
	if sheet_window and sheet_window.visible:
		dock_sheet()
		return
	machine.release_carriage_controls()
	if focus_paper:toggle_focus()
	if not sheet_window:
		sheet_window=preload("res://SheetWindow.gd").new()
		sheet_window.setup(self,right)
	view_button.hide()
	pop_sheet_button.text="Dock sheet"
	pop_sheet_button.tooltip_text="Return the sheet to the writing room"
	dock_sheet_button.show()
	sheet_window.open(right)
	sync()

func dock_sheet():
	if not sheet_window or not sheet_window.visible:return
	sheet_window.close_to_dock(right)
	view_button.show()
	dock_sheet_button.hide()
	pop_sheet_button.text="Pop out"
	pop_sheet_button.tooltip_text="Open the sheet in a separate, resizable window"
	sync()

func toggle_focus():
	if sheet_window and sheet_window.visible:
		if sheet_window.has_focus():get_window().grab_focus()
		else:sheet_window.grab_focus()
		return
	machine.release_carriage_controls()
	focus_paper=not focus_paper;left.visible=not focus_paper;view_button.text="Operator view" if focus_paper else "Enlarge";paper.queue_redraw()
func notice(txt:String):note=txt;note_time=4.;sync()
func changed():save_tick=.4;sync()
func sync():
	if not paper:return
	mechanism_audio.master_gain=writer.data.volume
	mechanism_audio.key_gain=writer.data.keys_volume
	mechanism_audio.mechanism_gain=writer.data.controls_volume
	mechanism_audio.spatial=writer.data.spatial_audio
	machine.sync();paper.queue_redraw();reading_line.carbon_view=paper.carbon;reading_line.queue_redraw()
	var d=writer.data
	if viewed_page>=d.finished_pages.size():
		viewed_page=-1
		paper.show_finished(null)
	var browsing=viewed_page>=0
	if browsing:
		page_title.text=("%s %d of %d"%["Carbon" if paper.carbon else "Page",viewed_page+1,d.finished_pages.size()])
	elif not d.sheet_loaded:page_title.text="Empty platen"
	else:page_title.text="Carbon copy" if paper.carbon else ("Postcard" if d.paper=="Postcard" else "The sheet")
	stack_action.text="Stack sheet" if d.sheet_loaded else "Load sheet"
	stack_action.visible=not browsing or not d.sheet_loaded
	previous_page.text="‹ Previous" if browsing else "Stack (%d)"%d.finished_pages.size()
	previous_page.disabled=viewed_page==0 or d.finished_pages.is_empty()
	next_page.visible=browsing
	next_page.disabled=viewed_page+1>=d.finished_pages.size()
	draft_button.visible=browsing and d.sheet_loaded
	line_title.visible=not browsing and d.sheet_loaded
	reading_line.visible=line_title.visible
	if sheet_window and sheet_window.visible:sheet_window.title="Typewriter Emulator • "+machine_profile.nickname+" — "+page_title.text
	ribbon_button.select(machine_profile.ribbon_modes.find(d.ribbon))
	replay_button.disabled=d.events.is_empty() or browsing
	queue_button.text="Paste & type" if paste_text.is_empty() else (("Resume" if paused else "Pause")+"  ·  "+str(paste_text.length()))
	if note_time>0:status.text=note
	elif browsing:status.text="Reading the finished stack"
	elif not d.sheet_loaded:status.text="Load a sheet to type"
	elif writer.carriage_held():status.text="Carriage released   ·   Drag or use ← / →"
	else:status.text="Jam • use Margin release" if d.jammed else ("Physical keyboard layout" if d.physical else "Type to write   ·   Click any impression to replay")
	info.text=("SHIFT LOCK    " if d.locked else "")+("MARGIN RELEASE    " if writer.margin_bypassed() else "")+"Line %s    Column %d    %s"%[str(snappedf(1.+float(d.half)/2.,.01)),int(d.col)+1,d.paper]
func _process(dt):
	wooting.poll()
	if wooting_status and wooting_status.text!=wooting.status:wooting_status.text=wooting.status
	if save_tick>=0:
		save_tick-=dt
		if save_tick<0 and not test_mode and not writer.save_file(machine_profile.autosave_path):notice("Autosave failed • use Save as")
	if note_time>0:
		note_time-=dt
		if note_time<=0:sync()
	if not paused and not paste_text.is_empty() and not writer.carriage_held() and not writer.data.center_locked:
		paste_tick-=dt
		if paste_tick<=0:
			var ch=paste_text[0];if type_char(ch):paste_text=paste_text.substr(1)
			paste_tick=writer.paste_interval(ch,paste_text[0] if not paste_text.is_empty() else "",pace);sync()
	if recording:
		record_tick-=dt
		if record_tick<=0:
			record_tick=.0833
			var im=get_viewport().get_texture().get_image();im.resize(448,roundi(448.*im.get_height()/im.get_width()),Image.INTERPOLATE_BILINEAR);im.convert(Image.FORMAT_RGB8)
			if not frames.is_empty() and im.get_height()!=frames[0].get_height():im.resize(448,frames[0].get_height())
			frames.append(im)
			if frames.size()>=60:
				recording=false;notice("Saved "+record_path.get_file() if Publish.gif(record_path,frames) else "Could not save recording");frames.clear()
func _notification(what):
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		lock_chord_pending=false;shift_tap_location=-1
		release_margin_key()
		wooting.samples.clear()
	if what==NOTIFICATION_WM_CLOSE_REQUEST and writer and not test_mode:writer.save_file(machine_profile.autosave_path)
func _exit_tree():
	wooting.clean_up()
func toggle_shift_lock():
	writer.data.locked=not writer.data.locked
	changed()
	notice("Shift Lock engaged" if writer.data.locked else "Shift Lock released")

func handle_shift_lock(e:InputEventKey)->bool:
	var key=e.physical_keycode
	if e.echo:return false
	if shift_tap_location!=-1 and e.pressed and e.shift_pressed and not (e.ctrl_pressed or e.alt_pressed or e.meta_pressed) and e.unicode>=32:
		# The finger still holds the segment up for this stroke after tripping the latch.
		if writer.data.locked:toggle_shift_lock()
	if e.pressed:
		shift_tap_location=e.location if key==KEY_SHIFT and e.location==machine_profile.keyboard.SHIFT_RELEASE_LOCATION and writer.data.locked and not (e.ctrl_pressed or e.alt_pressed or e.meta_pressed) else -1
	if key not in [KEY_CTRL,KEY_SHIFT]:
		if e.pressed:lock_chord_pending=false
		return false
	if e.pressed:
		lock_chord_pending=not e.alt_pressed and not e.meta_pressed and ((key==KEY_CTRL and e.shift_pressed) or (key==KEY_SHIFT and e.ctrl_pressed))
	elif lock_chord_pending:
		lock_chord_pending=false
		toggle_shift_lock()
		return true
	elif key==KEY_SHIFT and shift_tap_location==e.location:
		shift_tap_location=-1
		if writer.data.locked:toggle_shift_lock()
		return true
	return false

func _input(e):
	if not writer or not e is InputEventKey:return
	if e.physical_keycode in [KEY_CAPSLOCK,KEY_F13] or e.keycode in [KEY_CAPSLOCK,KEY_F13]:
		if e.pressed:shift_tap_location=-1;lock_chord_pending=false
		return
	if settings.visible or file_dialog.visible or prompt.visible:
		machine.release_carriage_controls()
		lock_chord_pending=false;shift_tap_location=-1
		release_margin_key()
		return
	if handle_shift_lock(e):get_viewport().set_input_as_handled();return
	var keyboard=e.physical_keycode if e.physical_keycode!=KEY_NONE else e.keycode
	if keyboard in [KEY_HOME,KEY_END]:
		var side="left" if keyboard==KEY_HOME else "right"
		if not e.pressed or not (e.alt_pressed or e.ctrl_pressed or e.meta_pressed or e.shift_pressed):
			if not e.echo:machine.hold_carriage(side,"key_"+side,e.pressed)
			get_viewport().set_input_as_handled();return
	if e.pressed and e.alt_pressed and not (e.ctrl_pressed or e.meta_pressed or e.shift_pressed) and keyboard in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
		if not e.echo:
			var side="left" if keyboard==KEY_BRACKETLEFT else "right"
			machine.carriage_rig.tap("Flying margin "+side)
			set_margin_here(side)
		get_viewport().set_input_as_handled();return
	if e.pressed and writer.carriage_held() and keyboard in [KEY_LEFT,KEY_RIGHT]:
		writer.slide_carriage(writer.carriage_column()+(-1 if keyboard==KEY_LEFT else 1))
		changed();get_viewport().set_input_as_handled();return
	if not e.pressed and active_margin_key!=KEY_NONE and keyboard==active_margin_key:
		release_margin_key();get_viewport().set_input_as_handled();return
	if not e.pressed:return
	if not (e.ctrl_pressed or e.alt_pressed or e.meta_pressed) and (keyboard==KEY_BACKSLASH or e.unicode in [92,124]):
		if not e.echo and active_margin_key==KEY_NONE:
			if keyboard==KEY_NONE:tap_margin_release()
			else:
				active_margin_key=keyboard;press_margin_release();machine.set_margin_key(true)
		get_viewport().set_input_as_handled();return
	if not e.ctrl_pressed and not e.alt_pressed and keyboard in shortcut_keys.values():
		match shortcut_keys.find_key(keyboard):
			"Cutaway":toggle_cut()
			"Replay":replay_last()
			"Page view":toggle_focus()
		get_viewport().set_input_as_handled();return
	if e.ctrl_pressed:
		var letter=e.keycode if e.keycode!=KEY_NONE else keyboard
		if e.alt_pressed and e.shift_pressed and not e.meta_pressed and machine_profile.keyboard.SHORTCUTS.has(letter):
			if not e.echo:type_char(machine_profile.keyboard.SHORTCUTS[letter],Wooting.hid_for(keyboard),-1.,true)
			get_viewport().set_input_as_handled();return
		if e.alt_pressed and e.shift_pressed and not e.meta_pressed and keyboard>=KEY_1 and keyboard<=KEY_4:
			if not e.echo:set_touch_position(keyboard-KEY_1)
			get_viewport().set_input_as_handled();return
		if not (e.alt_pressed or e.meta_pressed) and machine_shortcut(keyboard,e):
			get_viewport().set_input_as_handled();return
		match keyboard:
			KEY_V:paste_or_pause()
			KEY_S:
				if save_path.is_empty() or e.shift_pressed:dialog("Save")
				else:notice("Saved "+save_path.get_file() if writer.save_file(save_path) else "Save failed")
			KEY_O:dialog("Open")
			KEY_N:confirm_sheet("Letter")
			KEY_P:dialog("Print PDF")
			_:return
	elif e.alt_pressed:
		if keyboard==KEY_UP:roll_page(-1)
		elif keyboard==KEY_DOWN:roll_page(1)
		else:return
	else:
		match keyboard:
			KEY_ESCAPE:
				if not paste_text.is_empty():paste_text="";paused=false;notice("Paste stopped")
				elif writer.data.jammed:tap_margin_release()
			KEY_ENTER,KEY_KP_ENTER:type_char("\n",0 if e.echo else Wooting.hid_for(keyboard))
			KEY_TAB:type_char("\t",0 if e.echo else Wooting.hid_for(keyboard))
			KEY_BACKSPACE:type_char("\b",0 if e.echo else Wooting.hid_for(keyboard))
			KEY_SPACE:type_char(" ",0 if e.echo else Wooting.hid_for(keyboard))
			_:
				if writer.data.physical:
					var physical=physical_pair(keyboard)
					if physical!="":physical_click(physical,e.shift_pressed,0 if e.echo else Wooting.hid_for(keyboard))
					elif e.unicode>=32:notice("This position has no mapped "+machine_profile.nickname+" key")
				elif e.unicode>=32:
					for ch in writer.expanded(char(e.unicode)):type_char(ch,0 if e.echo else Wooting.hid_for(keyboard))
				else:return
	get_viewport().set_input_as_handled()
func physical_pair(k:int)->String:
	return machine_profile.keyboard.physical_pair(k)
func check(ok:bool,label:String):
	if not ok:test_failures.append(label);push_error("Desktop verification: "+label)
func test_operator_keys(physical:bool):
	writer.reset();writer.data.physical=physical
	var shift=InputEventKey.new()
	shift.keycode=KEY_SHIFT;shift.physical_keycode=KEY_SHIFT
	for side in [KEY_LOCATION_LEFT,KEY_LOCATION_RIGHT]:
		writer.data.locked=true
		shift.location=side;shift.pressed=true;_input(shift);shift.pressed=false;_input(shift)
		check(writer.data.locked==(side==KEY_LOCATION_RIGHT),"only left Shift releases the latch")
		writer.data.locked=false
		shift.pressed=true;_input(shift);shift.pressed=false;_input(shift)
		check(not writer.data.locked,"unlatched Shift tap remains momentary")
	for pair in [[KEY_CAPSLOCK,KEY_CAPSLOCK],[KEY_F13,KEY_F13],[KEY_CAPSLOCK,KEY_F13]]:
		var reserved=InputEventKey.new()
		reserved.physical_keycode=pair[0];reserved.keycode=pair[1];reserved.pressed=true;_input(reserved)
		reserved.pressed=false;_input(reserved)
		check(not writer.data.locked and writer.data.events.is_empty(),"reserved PTT key leaves writing state alone")
	writer.data.locked=true;shift.location=KEY_LOCATION_LEFT;shift.pressed=true;_input(shift)
	var capital=InputEventKey.new();capital.physical_keycode=KEY_A;capital.keycode=KEY_A;capital.unicode=65;capital.shift_pressed=true;capital.pressed=true
	_input(capital);shift.pressed=false;_input(shift)
	check(not writer.data.locked and writer.data.events.back().glyph=="A","a held Shift carries its stroke after the latch releases")
	writer.reset();writer.data.physical=physical
	for locked in [false,true]:
		writer.data.locked=locked
		for sample in [[KEY_C,"ç","ç / é"],[KEY_E,"é","ç / é"],[KEY_Q,"¼","¼ / ½"],[KEY_H,"½","¼ / ½"],[KEY_P,"¢","@ / ¢"]]:
			var letter=sample[0]
			var chord=InputEventKey.new()
			chord.keycode=letter;chord.physical_keycode=letter
			chord.ctrl_pressed=true;chord.alt_pressed=true;chord.shift_pressed=true
			var count=writer.data.events.size()
			chord.pressed=true;_input(chord)
			chord.echo=true;_input(chord)
			chord.echo=false;chord.pressed=false;_input(chord)
			check(writer.data.events.size()==count+1 and writer.data.events.back().glyph==sample[1] and writer.data.events.back().key==sample[2] and writer.data.locked==locked,"shortcut strikes "+sample[1]+" once and preserves Shift Lock")
	writer.reset();writer.data.physical=physical
	var release=InputEventKey.new()
	release.keycode=KEY_BACKSLASH;release.physical_keycode=KEY_BACKSLASH
	for glyph in [92,124]:
		writer.data.left=1;writer.data.right=3;writer.move_col(4)
		type_char("x");check(writer.data.events.is_empty(),"line lock stops strike")
		release.unicode=glyph;release.shift_pressed=glyph==124;release.pressed=true;_input(release)
		check(writer.margin_held,"margin release responds to downstroke")
		release.echo=true;_input(release);release.echo=false;release.pressed=false;_input(release)
		check(not writer.margin_held and writer.data.margin_released,"release passes the stop")
		type_char("x");check(writer.data.events.size()==1 and writer.data.events[0].col==4,"margin key leaves the first extra cell for ink")
		type_char("\n");check(writer.data.col==1 and not writer.data.margin_released,"return restores stops")
		release.pressed=true;_input(release);type_char("\n")
		check(writer.data.col==writer.rail_left(),"held override returns past left margin")
		release.pressed=false;_input(release)
		writer.reset();writer.data.physical=physical
	writer.data.jammed=true;physical_click("⇄",false)
	check(not writer.data.jammed and writer.data.col==0,"service key clears a jam without tabbing")
	writer.data.locked=true;physical_click("Right shift",false)
	check(writer.data.locked and not shift_mouse,"right Shift leaves the latch engaged")
	writer.data.locked=true;physical_click("Left shift",false)
	check(not writer.data.locked and not shift_mouse,"left Shift releases the latch")
	writer.data.locked=true
	shift.pressed=true;handle_shift_lock(shift)
	var ctrl=InputEventKey.new();ctrl.physical_keycode=KEY_CTRL;ctrl.pressed=true;ctrl.shift_pressed=true
	handle_shift_lock(ctrl)
	var save=InputEventKey.new();save.physical_keycode=KEY_S;save.pressed=true;save.ctrl_pressed=true;save.shift_pressed=true
	check(not handle_shift_lock(save),"Shift-first Save As dispatches normally")
	ctrl.pressed=false;handle_shift_lock(ctrl);shift.pressed=false;handle_shift_lock(shift)
	check(writer.data.locked,"Shift-first Save As preserves the engaged latch")
	writer.move_col(writer.rail_right())
	writer.set_margin_held(true);writer.set_margin_held(false)
	type_char("x");type_char("x")
	check(writer.data.events.size()==1 and writer.message.begins_with("Paper edge"),"release cannot type beyond the last printable cell")
	writer.reset()
func test_carriage_inputs():
	writer.reset()
	writer.move_col(writer.bank_center_column())
	sync()
	machine.travel=machine.target_travel
	machine._process(.16)
	var cell=machine.camera.unproject_position(Vector3.RIGHT*.025)-machine.camera.unproject_position(Vector3.ZERO)
	var mouse=InputEventMouseButton.new()
	mouse.button_index=MOUSE_BUTTON_LEFT
	for side in ["left","right"]:
		var col=writer.carriage_column()
		mouse.position=machine.camera.unproject_position(machine.carriage_rig.point("Carriage release "+side))
		mouse.pressed=true
		machine._gui_input(mouse)
		check(writer.carriage_release_held(side),"click the "+side+" end release")
		var motion=InputEventMouseMotion.new()
		motion.position=mouse.position-cell*2.25
		motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		machine._gui_input(motion)
		check(absf(writer.carriage_column()-col-2.25)<.002,"unseated column follows pointer")
		mouse.pressed=false
		mouse.position=Vector2(-20.,-10.)
		machine._gui_input(mouse)
		check(not writer.carriage_held() and writer.data.col==int(col)+3,"off-model mouse-up seats the dog")
		machine._process(.5)
	var nav=InputEventKey.new()
	nav.pressed=true;nav.physical_keycode=KEY_HOME;_input(nav)
	nav.physical_keycode=KEY_END;_input(nav)
	nav.physical_keycode=KEY_HOME;nav.pressed=false;_input(nav)
	check(writer.carriage_release_held("right"),"hold either keyboard release independently")
	nav.physical_keycode=KEY_BRACKETLEFT;nav.alt_pressed=true;nav.pressed=true;_input(nav)
	var left_col=int(writer.data.col)
	check(writer.data.left==left_col,"set left margin while right release is held")
	nav.alt_pressed=false;nav.physical_keycode=KEY_RIGHT;_input(nav)
	mouse.position=machine.camera.unproject_position(machine.carriage_rig.point("Flying margin right"))
	mouse.pressed=true;machine._gui_input(mouse)
	mouse.pressed=false;machine._gui_input(mouse)
	check(writer.data.right==left_col+1,"pick moving right setter while carriage held")
	machine.release_carriage_controls()
	check(not writer.carriage_held(),"release cleanly on focus change")
	writer.reset()
	sync()

func run_test():
	await get_tree().process_frame
	preload("res://HandsOnChecks.gd").run(self)
	preload("res://PaperSupportChecks.gd").run(self)
	preload("res://DoubleClickChecks.gd").run(self)
	preload("res://ActionGrabChecks.gd").run(self)
	preload("res://ControlChecks.gd").run(self)
	preload("res://CarriageChecks.gd").run(self)
	preload("res://TouchLeverChecks.gd").run(self)
	preload("res://FinishedPageChecks.gd").run(self)
	test_carriage_inputs()
	for physical in [false,true]:
		test_operator_keys(physical)
		writer.data.physical=physical
		var second=KEY_CTRL if physical else KEY_SHIFT
		var chord=InputEventKey.new()
		chord.physical_keycode=second;chord.pressed=true
		chord.ctrl_pressed=second==KEY_SHIFT;chord.shift_pressed=second==KEY_CTRL
		_input(chord);chord.pressed=false;_input(chord)
		check(writer.data.locked,"Shift Lock engages in both layouts")
		var typed=InputEventKey.new();typed.physical_keycode=KEY_MINUS;typed.unicode=45;typed.pressed=true
		_input(typed);check(writer.data.events.back().glyph=="/","Shift Lock selects shifted punctuation")
		chord.pressed=true;_input(chord);chord.pressed=false;_input(chord)
		check(not writer.data.locked,"Shift Lock releases")
		chord.pressed=true;handle_shift_lock(chord)
		var save=InputEventKey.new();save.physical_keycode=KEY_S;save.pressed=true;save.ctrl_pressed=true;save.shift_pressed=true
		check(not handle_shift_lock(save),"Save As passes through")
		chord.pressed=false;handle_shift_lock(chord);check(not writer.data.locked,"Save As leaves Shift Lock alone")
	writer.reset()
	var text="l1-/ êç É"
	check(writer.unsupported(text)==["É"],"runtime assertion")
	for ch in writer.expanded("l1-/ êç"):type_char(ch)
	check(writer.data.events[0].glyph=="l" and writer.data.events[1].glyph=="l","runtime assertion")
	check(writer.data.events[2].key==writer.data.events[3].key and writer.data.events[3].shift,"runtime assertion")
	check(writer.data.events[4].col==writer.data.events[5].col,"runtime assertion")
	type_char("\b");type_char("x");type_char("\n");roll_page(1);type_char("2");roll_page(-1);type_char("O")
	check(writer.data.events.back().half==2,"runtime assertion")
	var dir=OS.get_environment("TEMP")+"/godiva-player-tools/"
	check(writer.save_file(dir+"verification.godiva"),"runtime assertion")
	var again=Writer.new(writer.meta,machine_profile);check(again.load_file(dir+"verification.godiva"),"session reload")
	check(again.raster.get_data()==writer.raster.get_data(),"runtime assertion")
	var legacy=writer.data.duplicate(true);legacy.erase("margin_released");legacy.erase("machine_id")
	var legacy_file=FileAccess.open(dir+"legacy-margin.godiva",FileAccess.WRITE);legacy_file.store_string(JSON.stringify(legacy));legacy_file.close()
	check(again.load_file(dir+"legacy-margin.godiva") and not again.margin_bypassed(),"legacy document restores with its original stops")
	check(again.data.machine_id==machine_profile.id and again.raster.get_data()==writer.raster.get_data(),"legacy Godiva sessions acquire provenance without changing their impressions")
	var foreign=legacy.duplicate(true)
	foreign.machine_id="other-machine"
	var foreign_file=FileAccess.open(dir+"foreign-machine.godiva",FileAccess.WRITE)
	foreign_file.store_string(JSON.stringify(foreign));foreign_file.close()
	check(not again.load_file(dir+"foreign-machine.godiva") and again.data.machine_id==machine_profile.id,"opening another machine's draft preserves the active document")
	again.move_col(again.data.right+1);again.set_margin_held(true)
	check(again.save_file(dir+"beyond-margin.godiva") and again.load_file(dir+"beyond-margin.godiva"),"save beyond right margin")
	check(again.data.margin_released and not again.margin_held,"restore the released margin with key at rest")
	check(Publish.pdf(dir+"verification.pdf",writer.export_image(false),false),"runtime assertion")
	check(writer.save_file(dir+"verification.godiva") and writer.save_file(dir+"verification.godiva"),"repeated atomic saves")
	writer.reset();writer.data.carbon=true;writer.data.ribbon="Stencil";type_char("H")
	check(writer.carbon_page.get_pixel(0,0)!=writer.raster.get_pixel(0,0),"carbon stock")
	check(writer.carbon_page.get_used_rect().size==writer.dimensions(),"carbon page size")
	var blank=Writer.new(writer.meta,machine_profile)
	check(writer.carbon_page.get_data()!=blank.carbon_page.get_data(),"stencil carbon transfer")
	writer.reset();var shiftpress=InputEventKey.new();shiftpress.physical_keycode=KEY_A;shiftpress.keycode=KEY_A;shiftpress.unicode=97;shiftpress.pressed=true
	Input.parse_input_event(shiftpress);await get_tree().process_frame;await get_tree().process_frame
	check(writer.data.events.size()==1 and writer.data.events[0].glyph=="a","physical input dispatch")
	writer.reset();writer.data.right=4
	for ch in "ab cd":type_char(ch)
	type_char("e");check(writer.data.col==5 and writer.data.events.size()==4,"margin stop")
	writer.reset()
	for c in writer.meta.chars:
		writer.data.col=0
		var printed=writer.action(c,Time.get_ticks_msec())
		check(not printed.is_empty() and writer.meta.chars.has(printed.glyph),"registered glyph "+c)
	check(writer.data.events.size()==88,"all 88 characters")
	writer.reset()
	var gif_frame=Image.create(32,24,false,Image.FORMAT_RGB8);gif_frame.fill(Color.RED)
	check(Publish.gif(dir+"verification.gif",[gif_frame,gif_frame]),"GIF export")
	if "--screenshot" in OS.get_cmdline_user_args():
		writer.reset();await get_tree().process_frame
		var pos=machine.global_position+machine.camera.unproject_position(machine.vec(machine.keys["L"]))
		var click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.position=pos;click.global_position=pos;click.pressed=true
		Input.parse_input_event(click);await get_tree().process_frame;await get_tree().process_frame
		check(writer.data.events.size()==1 and writer.data.events[0].key=="L","clicking the 3D L key")
		click=click.duplicate();click.pressed=false;Input.parse_input_event(click);await get_tree().process_frame
		writer.reset();note_time=0;for ch in writer.expanded("The quick brown fox jumps over the lazy dog.\nGodiva, Hermes 3000."):type_char(ch)
		await get_tree().create_timer(1.0).timeout
		get_viewport().get_texture().get_image().save_png(dir+"desktop.png")
	if not test_failures.is_empty():get_tree().quit(1);return
	# Exercise the real input-to-contact delay as a live writer would.
	test_mode=false
	writer.reset();type_char("l");var clean=blank.raster.get_data()
	check(writer.raster.get_data()==clean,"ink waits for contact")
	await get_tree().create_timer(.11).timeout
	check(writer.raster.get_data()!=clean,"ink deposited on impact")
	# Simulate late-arriving travel, as when actuation is configured very shallow.
	for physical in [false,true]:
		writer.reset();writer.data.physical=physical
		wooting.connected=true
		var l_key=InputEventKey.new()
		l_key.keycode=KEY_L;l_key.physical_keycode=KEY_L;l_key.unicode=108;l_key.pressed=true
		for speed in [8.,85.]:
			var sample_time=Time.get_unix_time_from_system()*1000.
			_input(l_key)
			wooting.samples.append([Wooting.hid_for(KEY_L),sample_time,speed])
			await get_tree().create_timer(.08).timeout
		var light=writer.data.events[0];var firm=writer.data.events[1]
		check(light.get("downstroke_speed")==8. and firm.get("downstroke_speed")==85.,"one travel trace per physical stroke")
		check(light.power<firm.power and light.alpha<firm.alpha,"measured speed drives sound power and ink")
		check(writer.export_image(false,1).get_data()==writer.raster.get_data(),"measured impressions replay exactly")
		_input(l_key)
		await get_tree().create_timer(.08).timeout
		check(not writer.data.events[2].has("downstroke_speed"),"ordinary input keeps simulated touch")
		wooting.stop()
	test_mode=true;save_tick=-1.
	if not test_failures.is_empty():get_tree().quit(1);return
	mechanism_audio.stop_all()
	await get_tree().create_timer(.35).timeout
	print("GODIVA_DESKTOP_TEST_OK")
	get_tree().quit()





func draft_check():
	# Limit unattended persistence checks to a temporary Windows profile.
	if not ProjectSettings.globalize_path("user://").replace("\\","/").to_lower().begins_with(OS.get_environment("TEMP").replace("\\","/").to_lower()+"/godiva-player-tools/"):
		get_tree().quit(2);return
	if "--draft-check-write" in OS.get_cmdline_user_args():
		writer.reset()
		for c in writer.expanded("Godiva l1-/ ê"):type_char(c)
		await get_tree().create_timer(.85).timeout
		if not FileAccess.file_exists(machine_profile.autosave_path):get_tree().quit(3);return
		print("DRAFT_WRITTEN")
	else:
		var back=""
		for hit in writer.data.events:back+=str(hit.glyph)
		if back!="Godivall-/^e":push_error("Draft mismatch "+back);get_tree().quit(4);return
		print("DRAFT_RESTORED")
	get_tree().quit()

