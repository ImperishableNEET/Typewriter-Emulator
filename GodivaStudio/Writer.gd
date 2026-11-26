extends RefCounted
const PaperGrab=preload("res://PaperGrabs.gd")
const PITCH = 14
const MARGIN = 52
const LEADING = 23.7
## Original default kept for scripts that opened Godiva before profiles existed.
const AUTOSAVE = "user://current.godiva"
const BASE = 66
const HF = 1.625
var machine_profile
var data: Dictionary
var meta: Dictionary
var pressure: Image
var atlas: Image
var mappings := {}
var raster: Image
var carbon_page: Image
var texture: ImageTexture
var carbon_texture: ImageTexture
var roll := RandomNumberGenerator.new()
var profile:Dictionary
var last_time := -10000
var last_key := ""
var gesture_key := ""
var gesture_time := -1
var gesture_index := 0
var cadence_ratio := 1.
var touch_bias := 0.
var measured_touch := {}
var message := ""
var bell := false
var margin_held := false
var carriage_buttons := {"left":false,"right":false}
var hand_column := 0.
var cache := {}
var pending_ink := {}
func _init(metadata,model=null):
	# Legacy direct callers supplied only the Hermes linkage manifest.
	machine_profile=model if model else load("res://machines/godiva/Godiva.tres")
	meta=metadata
	profile=population_timing(JSON.parse_string(FileAccess.get_file_as_string("res://assets/timing.json")).profiles)
	atlas=machine_profile.strike_atlas.get_image()
	atlas.convert(Image.FORMAT_RGBA8);pressure=machine_profile.pressure_atlas.get_image()
	for label in meta.bars:
		var pair=pair_for(label)
		for i in [1,0]:
			mappings[pair[i]]=[label,i]
	mappings.merge(machine_profile.keyboard.ALIASES,true)
	reset()

func population_timing(profiles:Array)->Dictionary:
	# Average timing profiles with equal weight. The public edition supplies one
	# illustrative profile. Finger totals retain the input profiles' weights.
	var baseline={"median":0.,"intervals":{},"all":[0.,0.,0.,0.,0.],"fingers":{}}
	for person in profiles:
		baseline.median+=float(person.median)/profiles.size()
		for i in person.all.size():baseline.all[i]+=float(person.all[i])/profiles.size()
		for category in person.intervals:
			if not baseline.intervals.has(category):baseline.intervals[category]=[0.,0.,0.,0.,0.]
			for i in person.intervals[category].size():
				baseline.intervals[category][i]+=float(person.intervals[category][i])/profiles.size()
		for key in person.fingers:
			if not baseline.fingers.has(key):baseline.fingers[key]={}
			var votes:Dictionary=baseline.fingers[key]
			for digit in person.fingers[key]:
				votes[digit]=int(votes.get(digit,0))+int(person.fingers[key][digit])
	return baseline
func pair_for(key:String)->Array:
	return machine_profile.keyboard.faces_for(key)
func reset(stock:="Letter",rebuild_sheet:=true):
	data={"version":1,"machine_id":machine_profile.id,"paper":stock,"col":0,"half":0,"left":0,"right":67 if stock=="Letter" else 41,"spacing":1,"tabs":[8,16,24,32,40,48,56,64],"ribbon":"Black","direction":1,"ribbon_pos":3000,"wear":{},"freshness":0.9,"touch":0.45,"alignment":0.25,"mechanical":false,"physical":false,"carbon":false,"volume":0.65,"locked":false,"jammed":false,"events":[],"seed":randi(),"bail_left":0.22,"bail_right":0.78,"bail_up":false}
	data.keys_volume=1.
	data.sheet_loaded=true
	data.finished_pages=[]
	pending_ink.clear()
	data.controls_volume=1.
	data.spatial_audio=true
	data.base_cover=true
	data.inner_pan=true
	data.show_floor=true
	data.camera_collision=true
	PaperGrab.defaults(data)
	data.center_locked=false
	data.bail_lift=0.
	data.support_lift=1.
	data.margin_released=false
	data.touch_regulator=1
	margin_held=false
	clear_carriage_buttons()
	last_time=-10000
	last_key=""
	reset_gesture_history()
	if rebuild_sheet:rebuild()
func reset_mechanism():
	var previous=data
	reset(previous.paper,false)
	# Keep the material under the type guide, the existing impressions, and
	# the user's input preferences. Re-engage the feed at its current angle.
	for field in ["sheet_loaded","finished_pages","events","col","half","paper_side","paper_skew","platen_half","grip_half","ratchet_half","carbon","seed","physical","mechanical","keys_volume","controls_volume","spatial_audio","show_floor","camera_collision","volume","alignment","touch"]:
		data[field]=previous[field]
	hand_column=data.col
	data.margin_released=data.col>data.right
	message=""
	bell=false
	rebuild()

func new_stock(stock:String):
	var old=data.duplicate()
	var old_center=bank_center_column()
	reset(stock)
	data.finished_pages=old.finished_pages
	# The stops stay on the carriage when a differently sized sheet is centered.
	var offset=bank_center_column()-old_center
	data.tabs=old.tabs.map(func(col):return int(col)+offset)
	var default_right=67 if old.paper=="Letter" else 41
	if old.paper==stock or old.left!=0 or old.right!=default_right:
		data.left=clampi(int(old.left)+offset,rail_left(),rail_right()-1)
		data.right=clampi(int(old.right)+offset,int(data.left)+1,rail_right())
	move_col(data.left)
	PaperGrab.change_stock(data,old)
	for k in ["support_lift","bail_lift","bail_up","bail_left","bail_right","center_locked","ribbon","direction","ribbon_pos","wear","freshness","touch","touch_regulator","alignment","mechanical","physical","carbon","keys_volume","controls_volume","spatial_audio","show_floor","camera_collision","base_cover","inner_pan","volume","seed"]:
		data[k]=old[k]
	if data.center_locked:data.col=bank_center_column()
func stock_dimensions(stock:String)->Vector2i:return Vector2i(1110,1436) if stock=="Letter" else Vector2i(740,482)
func dimensions()->Vector2i:return stock_dimensions(data.paper)

func finish_page()->bool:
	if not data.sheet_loaded:return false
	# Freeze the visible impressions, including overstrikes, skew, ribbon wear
	# and individual carbon strikes. A future atlas revision cannot change them.
	var page={"machine_id":machine_profile.id,"paper":data.paper,"events":[],"carbon":data.carbon,"col":data.col,"half":data.half,
		"finished_at":int(Time.get_unix_time_from_system()),"paper_side":data.paper_side,"paper_skew":data.paper_skew}
	for i in data.events.size():
		if pending_ink.has(i):continue
		var event:Dictionary=data.events[i]
		page.events.append(event.duplicate(true))
		if event.carbon:page.carbon=true
	page.impression_png=Marshalls.raw_to_base64(raster.save_png_to_buffer())
	page.page_id=Crypto.new().generate_random_bytes(16).hex_encode()
	page.carbon_png=Marshalls.raw_to_base64(carbon_page.save_png_to_buffer())
	if page.impression_png.is_empty() or page.carbon_png.is_empty():return false
	data.finished_pages.append(page)
	data.sheet_loaded=false
	data.events=[]
	pending_ink.clear()
	last_key=""
	last_time=-10000
	message=""
	bell=false
	rebuild()
	return true

func finished_image(index:int,carbon:=false)->Image:
	if index<0 or index>=data.finished_pages.size():return null
	var page:Dictionary=data.finished_pages[index]
	return decode_finished_image(page.carbon_png if carbon else page.impression_png,stock_dimensions(page.paper))

func decode_finished_image(encoded:String,dims:Vector2i)->Image:
	var bytes=Marshalls.base64_to_raw(encoded)
	# Validate IHDR dimensions before letting the decoder allocate the image.
	if bytes.size()<33 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]):return null
	var stream=StreamPeerBuffer.new()
	stream.big_endian=true
	stream.data_array=bytes
	stream.seek(16)
	if stream.get_u32()!=dims.x or stream.get_u32()!=dims.y:return null
	var image=Image.new()
	return image if image.load_png_from_buffer(bytes)==OK else null
func bank_center_column()->int:return roundi((dimensions().x*.5-MARGIN)/PITCH-.5)
func max_col()->int:return floori((dimensions().x-2*MARGIN)/float(PITCH))-1
func rail_left()->int:return ceili(-float(MARGIN)/PITCH)
func rail_right()->int:return floori(float(dimensions().x-MARGIN)/PITCH)-1
func carriage_held()->bool:
	return carriage_buttons.left or carriage_buttons.right
func carriage_release_held(side:String)->bool:
	return carriage_buttons.get(side,false)
func carriage_column()->float:
	return hand_column if carriage_held() else float(data.col)
func clear_carriage_buttons():
	carriage_buttons.left=false
	carriage_buttons.right=false
	hand_column=float(data.col)
func set_carriage_release(side:String,held:bool):
	if held and data.center_locked:return
	if not carriage_buttons.has(side) or carriage_buttons[side]==held:return
	if held and not carriage_held():hand_column=float(data.col)
	carriage_buttons[side]=held
	if not carriage_held():hand_column=float(data.col)
func slide_carriage(column:float):
	if data.center_locked or not carriage_held() or not is_finite(column):return
	hand_column=clampf(column,rail_left(),rail_right())
	# When the working dog returns, spring pull seats the first tooth ahead.
	# Keep that cell in saved sheets; only the live hand position is fractional.
	move_col(ceili(hand_column-1e-8))
func set_flying_margin(side:String)->bool:
	if data.center_locked:return false
	var col=int(data.col)
	if col<rail_left() or col>rail_right():return false
	match side:
		"left":
			if col>=data.right:return false
			data.left=col
		"right":
			if col<=data.left:return false
			data.right=col
			data.margin_released=false
		_:return false
	return true
func margin_bypassed()->bool:return margin_held or data.margin_released
func set_margin_held(held:bool):
	if held==margin_held:return
	margin_held=held
	if data.col>data.right:data.margin_released=true
	if held:data.jammed=false
func max_half()->int:return floori((dimensions().y-BASE-36)/(LEADING/2))
func rebuild():
	var dims=dimensions()
	raster=Image.create(dims.x,dims.y,false,Image.FORMAT_RGBA8)
	carbon_page=Image.create(dims.x,dims.y,false,Image.FORMAT_RGBA8)
	raster.fill(Color("#f5f0df"));carbon_page.fill(Color("#e3e8dc"))
	for event in data.events:stamp(event,raster,carbon_page,1)
	texture=ImageTexture.create_from_image(raster)
	carbon_texture=ImageTexture.create_from_image(carbon_page)
func expanded(text:String)->String:
	var out=""
	for ch in text.replace("\r\n","\n").replace("\r","\n"):
		out+=str(machine_profile.keyboard.COMPOSE.get(ch,ch))
	return out
func unsupported(text:String)->Array:
	var bad=[]
	for ch in expanded(text):
		if not mappings.has(ch) and ch not in [" ","\n","\t"] and ch not in bad:bad.append(ch)
	return bad
func move_col(n):
	if data.center_locked:return
	data.col=clampi(n,rail_left(),rail_right()+1)
	if data.col<=data.right:data.margin_released=false
	elif margin_held:data.margin_released=true
func turn(n):
	PaperGrab.turn(self,float(n))
func advance():
	if data.col<=data.right or margin_bypassed():move_col(data.col+1)
	if data.col==int(data.right)-5:bell=true
func transfer_factor(worn:float)->float:
	return (.38+.62*data.freshness)*(1.-minf(.72,worn*.06))

func set_touch_regulator(setting:int):
	data.touch_regulator=clampi(setting,0,3)

func adjusted_power(nominal:float,setting:int)->float:
	if setting==1:return nominal
	# Interpret the existing calibrated response as relative impact speed at II.
	# At equal operator input the change in spring work comes out of kinetic energy.
	var rig:Dictionary=meta.touch_rig
	var work:Array=rig.spring_work
	return sqrt(maxf(0.,nominal*nominal+(float(work[1])-float(work[setting]))/float(rig.nominal_energy)))

func reset_gesture_history():
	gesture_time=-1
	gesture_key=""
	gesture_index=0
	cadence_ratio=1.
	touch_bias=0.

func timing_quantiles(previous:String,key:String)->Array:
	if previous.is_empty():return profile.all
	# Finger assignments describe letter transitions. Service keys and punctuation use
	# the operator's overall interval distribution.
	if not profile.fingers.has(previous.to_lower()) or not profile.fingers.has(key.to_lower()):
		return profile.all
	if previous==key:return profile.intervals.repeat
	if hand(previous)!=hand(key):return profile.intervals.alternate
	if finger(previous)==finger(key):return profile.intervals.same_finger
	return profile.intervals.same_hand

func write_profile(gesture:Dictionary,fraction:float)->Dictionary:
	fraction=clampf(fraction,0.,1.)
	gesture.stroke_fraction=fraction
	gesture.force_fraction=fraction
	gesture.sound_tempo="quick" if fraction>=.68 else ("deliberate" if fraction<=.39 else "")
	gesture.motion_duration=lerpf(.151,.069,fraction)
	gesture.gain=lerpf(.70,1.15,fraction)
	return gesture

func touch_group(action_name:String)->String:
	if not meta.bars.has(action_name):return action_name
	var digit=finger(action_name)
	return "print/"+(digit if digit!="" else str(hand(action_name)))

func calibrated_touch(group:String)->Vector2:
	# Prior moments and pseudo-counts are tuning constants for normalized input.
	# Learn printing effort across fingers, shrinking each finger toward that
	# baseline. Service mechanisms have separate loads and observations.
	var center=.56
	var variance=.18*.18
	var groups=["print",group] if group.begins_with("print/") else [group]
	for g in groups:
		if not measured_touch.has(g):continue
		var sample:Vector3=measured_touch[g] # count, mean, variance
		var weight=sample.x/(sample.x+16.)
		var delta=sample.y-center
		variance=lerpf(variance,sample.z,weight)+weight*(1.-weight)*delta*delta
		center=lerpf(center,sample.y,weight)
	return Vector2(center,clampf(sqrt(variance),.075,.28))

func refine_profile(gesture:Dictionary,fraction:float)->Dictionary:
	if not is_finite(fraction) or fraction<0.:return gesture
	var observed=clampf(fraction,0.,1.)
	var group:String=gesture.get("touch_group","")
	if group!="" and not gesture.get("touch_measured",false):
		var baseline=calibrated_touch(group)
		# Preserve the exact sample for this stroke; limit its influence on the
		# fallback. After 64 observations the estimator slowly forgets old input.
		var robust=clampf(observed,baseline.x-2.5*baseline.y,baseline.x+2.5*baseline.y)
		var groups=["print",group] if group.begins_with("print/") else [group]
		for g in groups:
			var stats:Vector3=measured_touch.get(g,Vector3.ZERO)
			var count=minf(stats.x+1.,64.)
			var delta=robust-stats.y
			var mean=stats.y+delta/count
			var variance=(1.-1./count)*(stats.z+delta*delta/count)
			measured_touch[g]=Vector3(count,mean,variance)
		gesture.touch_measured=true
	return write_profile(gesture,observed)

func service_profile(action_name:String,clock:int,measured_fraction:float=-1.)->Dictionary:
	var q=timing_quantiles(gesture_key,action_name)
	var interval=clock-gesture_time
	var expected=float(q[2])
	var pace=0.
	if gesture_time>=0 and interval>0 and interval<1000:
		var ratio=clampf(expected/maxf(interval,32.),.35,2.5)
		pace=.65*log(ratio)+.35*log(cadence_ratio)
		cadence_ratio=lerpf(cadence_ratio,ratio,.18)
	elif interval>=1000:
		cadence_ratio=1.
	gesture_key=action_name
	gesture_time=clock
	gesture_index+=1
	var group=touch_group(action_name)
	var gesture={"touch_group":group}
	if measured_fraction>=0.:
		var observed=clampf(measured_fraction,0.,1.)
		touch_bias=lerpf(touch_bias,clampf(observed-.56,-.24,.24),.45)
		return refine_profile(gesture,observed)
	# Interval and finger data describe timing, not impact velocity. The bounded
	# conversion below supplies a mechanical approximation for digital input.
	var rng=RandomNumberGenerator.new()
	rng.seed=int(data.seed)+gesture_index*65537+action_name.hash()
	var spread=clampf((float(q[3])-float(q[1]))/maxf(1.,expected),.12,.70)
	# A sequence of strokes shares the typist's current touch. The correlation
	# decays in real time, and the bounded innovation restores session variance.
	var memory=exp(-clampf(float(interval),1.,4000.)/680.) if gesture_index>1 else 0.
	touch_bias=clampf(memory*touch_bias+sqrt(1.-memory*memory)*rng.randfn(0.,.13),-.28,.28)
	var reach=0.
	if meta.bars.has(action_name) and meta.keys.has(action_name):
		reach=absf(float(meta["keys"][action_name][2])-float(meta["keys"]["F"][2]))*.075
	var variation=clampf(float(data.touch),0.,1.)
	var estimated=calibrated_touch(group)
	var effort=(touch_bias+rng.randfn(0.,.095+.09*spread))*estimated.y/.18-reach
	var center=lerpf(.56,estimated.x,variation)
	var fraction=center+.31*pace+variation*effort
	write_profile(gesture,clampf(fraction,.09,.96))
	# Inter-key rhythm predicts attack timing better than force. A fast passage
	# can have a quick action and a light impression.
	gesture.force_fraction=clampf(center+variation*(effort+.055*pace),.04,.98)
	gesture.gain=lerpf(.70,1.15,gesture.force_fraction)
	var stats:Vector3=measured_touch.get("print" if group.begins_with("print/") else group,Vector3.ZERO)
	gesture.touch_confidence=stats.x/(stats.x+16.)
	return gesture

func apply_downstroke(event:Dictionary,speed:float,transfer:float,fraction:float):
	if not owns_event(event):return
	var was_miss:bool=event.miss
	refine_profile(event,fraction)
	event.power=adjusted_power(lerpf(.30,1.18,fraction),int(event.get("touch_regulator",1)))
	event.miss=bool(event.get("timing_miss",event.miss)) or event.power==0.
	event.alpha=clampf(event.power*transfer,.05,1.)
	event.downstroke_speed=speed
	if event.has("wear_bin") and not event.jam and event.ink!="Stencil" and was_miss!=event.miss:
		# The ribbon may have advanced, reversed or taken another hit in the
		# same cell while waiting for its travel packet. Adjust only this hit.
		var bin:String=event.wear_bin
		var count=float(data.wear.get(bin,0.))+(-1. if event.miss else 1.)
		if count>0.:data.wear[bin]=count
		else:data.wear.erase(bin)
	if not event.jam and not data.events.is_empty() and is_same(event,data.events.back()):
		if event.miss and message=="":message="Light strike • no ink reached the sheet"
		elif not event.miss and message=="Light strike • no ink reached the sheet":message=""

func jam_probability(gap_ms:int)->float:
	if data.events.is_empty() or last_key.is_empty():return 0.
	# At impact the bar is 46% through its action. It clears the shared
	# guide on the return before it finally settles into the basket.
	var duration=float(data.events.back().get("motion_duration",.105))
	var clearance_ms=1000.*duration*.72
	return .55*clampf(1.-float(gap_ms)/clearance_ms,0.,1.)

func action(ch:String,clock:int,defer_ink:=false,analog_candidate:=false,pointer_strength:float=-1.,exact_face:=false)->Dictionary:
	message="";bell=false
	if not data.sheet_loaded:
		message="Load a sheet to type"
		return {}
	if data.center_locked:
		message="Carriage centered • release the transport lock"
		return {}
	if carriage_held():
		message="Carriage released • let go to type"
		return {}
	if ch=="\n":
		if not data.paper_loose and float(data.half)+2*int(data.spacing)>max_half():message="Bottom of sheet";return {}
		data.margin_released=false
		move_col(rail_left() if margin_held else int(data.left))
		turn(2*int(data.spacing));return {}
	if ch=="\b":
		var stop=rail_left() if margin_held or data.col<data.left else int(data.left)
		move_col(maxi(stop,data.col-1));return {}
	if ch=="\t":
		var target=rail_right() if margin_bypassed() else int(data.right)
		for t in data.tabs:
			if t>data.col:target=mini(target,int(t))
		move_col(maxi(target,data.col));return {}
	if data.jammed:message="Typebars jammed • release to continue";return {}
	if data.col>rail_right():message="Paper edge • return the carriage";return {}
	if data.col>data.right and not margin_bypassed():message="Right margin • press \\ to continue or return the carriage";return {}
	if ch==" ":advance();return {}
	if not mappings.has(ch):message="No key for "+ch;return {}
	var key:String=mappings[ch][0]
	var shifted:bool=bool(mappings[ch][1]) or (data.locked and not exact_face)
	var face:String=pair_for(key)[int(shifted)]
	var gap=clock-last_time
	var index=data.events.size()
	roll.seed=int(data.seed)+index*7919+key.hash()
	var crowded=clampf(1.0-float(gap)/145.,0,1)
	var missed:bool=data.mechanical and gap<70 and roll.randf()<.10
	var risk=jam_probability(gap) if data.mechanical and last_key!=key else 0.
	var jam:bool=risk>0. and roll.randf()<risk
	if jam:data.jammed=true
	var gesture=service_profile(key,clock,pointer_strength)
	var previous_hand=hand(last_key)
	var same:float=1.0 if hand(key)==previous_hand else 0.0
	var nominal=clampf(.96+.44*(gesture.force_fraction-.56)-data.touch*crowded*(.13+.09*same),.24,1.18)
	var calibrated_power=lerpf(.30,1.18,gesture.force_fraction)
	if pointer_strength>=0.:nominal=calibrated_power
	else:nominal=lerpf(nominal,calibrated_power,float(gesture.get("touch_confidence",0.))*data.touch)
	var strength=adjusted_power(nominal,int(data.touch_regulator))
	var timing_miss=missed
	missed=missed or strength==0.
	var bin_key=str(floori(float(data.ribbon_pos)/3.0))+":"+str(data.ribbon)
	var worn=float(data.wear.get(bin_key,0))
	var e={"input":ch,"key":key,"glyph":face,"shift":shifted,"col":int(data.col),"half":float(data.half),"ink":data.ribbon,"power":strength,"alpha":clampf(strength*(.38+.62*data.freshness)*(1.-minf(.72,worn*.06)),.05,1.),"dx":data.alignment*(roll.randfn(0,.35)+sin(float(key.hash()%200))*.7),"dy":data.alignment*(roll.randfn(0,.39)+sin(float(key.hash()%70))*.82),"carbon":data.carbon,"miss":missed,"jam":jam}
	e.touch_regulator=int(data.touch_regulator)
	e.merge(gesture)
	if analog_candidate:
		e.wear_bin=bin_key
		e.ribbon_transfer=transfer_factor(worn)
		e.timing_miss=timing_miss
	if pointer_strength>=0.:e.pointer_strength=pointer_strength
	PaperGrab.register_strike(self,e)
	e.sheet_index=index
	data.events.append(e);last_time=clock;last_key=key
	if jam:message="Two bars caught • release the jam";return e
	pending_ink[index]=true
	if missed:message="Light strike • no ink reached the sheet"
	if data.ribbon!="Stencil" and not missed:data.wear[bin_key]=worn+1.
	data.ribbon_pos=preload("res://RibbonRig.gd").advance(float(data.ribbon_pos),int(data.direction),meta.ribbon_rig.transport)
	if data.ribbon_pos==6000:data.direction=-1
	elif data.ribbon_pos==0:data.direction=1
	if face not in machine_profile.keyboard.DEAD_FACES:advance()
	if not defer_ink:deposit(e)
	return e
func owns_event(e:Dictionary)->bool:
	var index=int(e.get("sheet_index",-1))
	return data.sheet_loaded and index>=0 and index<data.events.size() and is_same(e,data.events[index])

func deposit(e:Dictionary):
	if not owns_event(e) or not pending_ink.erase(int(e.sheet_index)):return
	stamp(e,raster,carbon_page,1);texture.update(raster);carbon_texture.update(carbon_page)
func finger(key:String)->String:
	var k=key.to_lower()
	if profile.fingers.has(k):
		var votes:Dictionary=profile.fingers[k];var best="";var count=0
		for f in votes:
			if votes[f]>count:best=f;count=votes[f]
		return best
	return ""
func paste_interval(previous:String,upcoming:String,speed:float)->float:
	if previous=="\n":return .38
	if not mappings.has(previous) or not mappings.has(upcoming):return 1./speed
	var a:String=mappings[previous][0];var b:String=mappings[upcoming][0]
	var q=timing_quantiles(a,b)
	var rng=RandomNumberGenerator.new();rng.seed=int(data.seed)+data.events.size()*137
	var sample=rng.randf_range(.7,3.3);var i=floori(sample)
	return clampf(lerpf(q[i],q[i+1],sample-i)/float(profile.median)/speed,.035,.6)
func hand(key:String)->int:
	var digit=finger(key)
	if digit.begins_with("L_"):return 0
	if digit.begins_with("R_"):return 1
	if meta["keys"].has(key):return int(meta["keys"][key][0]>=0.)
	return 0 if key.to_lower() in ["q","w","e","r","t","a","s","d","f","g","z","x","c","v","b"] else 1
func mask(ch:String,scale,contact:=false)->Image:
	var k=ch+str(scale)+str(contact)
	if not cache.has(k):
		var p=meta.chars[ch];var a=(pressure if contact else atlas).get_region(Rect2i(p[0],p[1],32,52))
		a.resize(PITCH*scale,roundi(PITCH*HF*scale),Image.INTERPOLATE_LANCZOS)
		cache[k]=a
	return cache[k]
func stamp(e:Dictionary,sheet:Image,copy:Image,scale:int):
	if e.jam or e.miss:return
	var a=mask(e.glyph,scale);var relief=mask(e.glyph,scale,true)
	var origin=Vector2i(roundi((MARGIN+int(e.col)*PITCH+e.dx)*scale),roundi((BASE+float(e.half)*LEADING*.5-1.125*PITCH+e.dy)*scale))
	for y in a.get_height():
		for x in a.get_width():
			var opacity=a.get_pixel(x,y).a
			var dent=relief.get_pixel(x,y).a
			if opacity<.002 and dent<.002:continue
			var p=origin+Vector2i(x,y)
			if p.x<0 or p.y<0 or p.x>=sheet.get_width() or p.y>=sheet.get_height():continue
			if e.ink!="Stencil":
				var red:bool=e.ink=="Red" or (e.ink=="Split" and y>a.get_height()*.44)
				var ink=Color("#8d2927") if red else Color("#242420")
				sheet.set_pixelv(p,sheet.get_pixelv(p).lerp(ink,clampf(opacity*e.alpha,0,1)))
			if e.ink=="Stencil" and dent>.02:
				var above=relief.get_pixel(x,maxi(y-1,0)).a
				var edge=(dent-above)*.09*e.power
				sheet.set_pixelv(p,sheet.get_pixelv(p).lerp(Color("#5a574f") if edge>=0 else Color.WHITE,absf(edge)))
			if e.carbon:copy.set_pixelv(p,copy.get_pixelv(p).lerp(Color("#263146"),minf(1.,dent*e.power*.43)))
func export_image(copy:bool,scale:=2)->Image:
	var size=dimensions()*scale
	var a=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8);var b=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
	a.fill(Color("#f5f0df"));b.fill(Color("#e3e8dc"))
	for e in data.events:stamp(e,a,b,scale)
	return b if copy else a
func save_file(path:String)->bool:
	var temp=path+".tmp"
	var f=FileAccess.open(temp,FileAccess.WRITE)
	if f==null:return false
	f.store_string(JSON.stringify(data));f.flush()
	var write_error=f.get_error()
	f.close()
	if write_error!=OK:return false
	var absolute=ProjectSettings.globalize_path(path)
	var prev=absolute+".bak"
	if FileAccess.file_exists(absolute):
		if FileAccess.file_exists(prev) and DirAccess.remove_absolute(prev)!=OK:return false
		if DirAccess.rename_absolute(absolute,prev)!=OK:return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),absolute)!=OK:
		if FileAccess.file_exists(prev):DirAccess.rename_absolute(prev,absolute)
		return false
	return true
func load_file(path:String)->bool:
	if not FileAccess.file_exists(path):return false
	var value=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("version")!=1:return false
	if value.get("machine_id","godiva")!=machine_profile.id:return false
	value.machine_id=machine_profile.id
	if not value.has("sheet_loaded"):value.sheet_loaded=true
	if not value.has("finished_pages"):value.finished_pages=[]
	if not value.sheet_loaded is bool or not value.finished_pages is Array:return false
	for page in value.finished_pages:
		if not valid_finished_page(page):return false
		if not page.has("machine_id"):page.machine_id="godiva"
	if not value.has("margin_released"):value.margin_released=false
	if not value.margin_released is bool:return false
	if not value.has("touch_regulator"):value.touch_regulator=1
	if typeof(value.touch_regulator) not in [TYPE_FLOAT,TYPE_INT]:return false
	if value.touch_regulator!=int(value.touch_regulator) or value.touch_regulator<0 or value.touch_regulator>3:return false
	value.touch_regulator=int(value.touch_regulator)
	for field in ["keys_volume","controls_volume"]:
		if not value.has(field):value[field]=1.
		if typeof(value[field]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(value[field]) or value[field]<0. or value[field]>1.:return false
	for flag in ["show_floor","camera_collision","base_cover","inner_pan"]:
		if not value.has(flag):value[flag]=true
		if not value[flag] is bool:return false
	if not value.has("spatial_audio"):value.spatial_audio=true
	if not value.spatial_audio is bool:return false
	if not PaperGrab.migrate(value):return false
	if not value.has("center_locked"):value.center_locked=false
	if not value.center_locked is bool:return false
	for prop in ["bail_lift","support_lift"]:
		if not value.has(prop):value[prop]=float(value.get("bail_up",false)) if prop=="bail_lift" else 1.
		if typeof(value[prop]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(value[prop])) or value[prop]<0 or value[prop]>1:return false
	# Older saves allowed continuously parked paper rests. Settle to the nearest stop.
	value.support_lift=roundf(float(value.support_lift))
	for k in data:
		if not value.has(k):return false
	for k in ["col","half","left","right","spacing","ribbon_pos","direction","seed","volume","touch","alignment","freshness","bail_left","bail_right"]:
		if typeof(value[k]) not in [TYPE_FLOAT,TYPE_INT]:return false
	for k in ["physical","mechanical","carbon","jammed","locked","bail_up"]:
		if not value[k] is bool:return false
	if value.ribbon not in machine_profile.ribbon_modes or not value.wear is Dictionary or not value.tabs is Array:return false
	for tab in value.tabs:
		if typeof(tab) not in [TYPE_FLOAT,TYPE_INT]:return false
	value.tabs=value.tabs.map(func(tab):return int(tab))
	for wear in value.wear.values():
		if typeof(wear) not in [TYPE_FLOAT,TYPE_INT]:return false
	if value.paper not in ["Letter","Postcard"] or not valid_events(value.events):return false
	if not value.sheet_loaded and not value.events.is_empty():return false
	data=value;pending_ink.clear();margin_held=false;clear_carriage_buttons();last_time=-10000;last_key="";reset_gesture_history();rebuild();return true

func valid_finished_page(page)->bool:
	if not page is Dictionary or page.get("paper") not in ["Letter","Postcard"]:return false
	if page.has("machine_id") and (not page.machine_id is String or page.machine_id.is_empty()):return false
	var source_id=page.get("machine_id","godiva")
	var source_meta=meta
	if source_id!=machine_profile.id:
		var desks=preload("res://machines/MachineShelf.gd").DESKS
		if not desks.has(source_id):return false
		source_meta=load(desks[source_id][2]).load_manifest()
	if not page.get("carbon") is bool or not valid_events(page.get("events"),source_meta):return false
	for k in ["col","half","finished_at","paper_side","paper_skew"]:
		if typeof(page.get(k)) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(page[k])):return false
	var dims=stock_dimensions(page.paper)
	for k in ["impression_png","carbon_png"]:
		if not page.get(k) is String or decode_finished_image(page[k],dims)==null:return false
	return true

func valid_events(events,source_meta=null)->bool:
	if source_meta==null:source_meta=meta
	if not events is Array:return false
	for e in events:
		if not e is Dictionary:return false
		for k in ["key","input","shift","glyph","ink","power","alpha","dx","dy","col","half","miss","jam","carbon"]:
			if not e.has(k):return false
		for k in ["col","half","power","alpha","dx","dy"]:
			if typeof(e[k]) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(e[k])):return false
		for k in ["miss","jam","shift","carbon"]:
			if not e[k] is bool:return false
		if not source_meta.chars.has(e.glyph) or not source_meta.bars.has(e.key):return false
	return true



