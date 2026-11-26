extends Node
## Each playing mechanism has a position and an independent voice.
var sound_directory:String
const ACTIONS=["bell","return","return_short","space","backspace","tab","jam","miss","platen","shift_press","shift_release"]
var bank={}
var strikes:Array[AudioStream]=[]
var tempo_bank={}
var orders={}
var last_take={}
var voices:Array[AudioStreamPlayer3D]=[]
var reserved={}
var cursor=0
var rng=RandomNumberGenerator.new()
var machine
var listener:AudioListener3D
var master_gain=1.
var key_gain=1.
var mechanism_gain=1.
var spatial=true

func _ready():
	rng.randomize()
	for tag in ACTIONS:
		var path=sound_directory+"/"+tag+".wav"
		if not ResourceLoader.exists(path):path=sound_directory+"/"+tag+"_mechanism.wav"
		bank[tag]=[load_sample(path)]
		var index=2
		while ResourceLoader.exists(sound_directory+"/"+tag+"_%02d.wav"%index):
			bank[tag].append(load_sample(sound_directory+"/"+tag+"_%02d.wav"%index))
			index+=1
	var index=1
	while ResourceLoader.exists(sound_directory+"/strike_%02d.wav"%index):
		strikes.append(load_sample(sound_directory+"/strike_%02d.wav"%index))
		index+=1
	bank["strike"]=strikes

func load_sample(path:String)->AudioStream:
	var stream=load(path)
	var stem=path.get_file().get_basename()
	var speeds={}
	for tempo in ["quick","deliberate"]:
		var variant=sound_directory+"/tempo/"+stem+"_"+tempo+".wav"
		if ResourceLoader.exists(variant):speeds[tempo]=load(variant)
	tempo_bank[stream]=speeds
	return stream

func bind_machine(host):
	machine=host
	voices.clear()
	reserved.clear()
	machine.view.audio_listener_enable_3d=true
	listener=AudioListener3D.new()
	machine.world.add_child(listener)
	listener.make_current()
	for i in 12:
		var voice=AudioStreamPlayer3D.new()
		voice.attenuation_model=AudioStreamPlayer3D.ATTENUATION_DISABLED
		voice.attenuation_filter_cutoff_hz=20500
		voice.max_db=3.
		machine.world.add_child(voice)
		voices.append(voice)
	reserved={"bell":voices[10],"return":voices[11],"return_short":voices[11]}
	update_listener()

func update_listener():
	var camera:Camera3D=machine.camera
	var basis=camera.global_transform.basis
	var distance=clampf(machine.zoom*.5,1.6,3.3)
	var eye_distance=maxf(0.,(camera.global_position-machine.inspection.focus).dot(basis.z))
	listener.global_transform=Transform3D(basis,camera.global_position-basis.z*maxf(0.,eye_distance-distance))

func select_take(tag:String)->int:
	var order:Array=orders.get(tag,[])
	if order.is_empty():
		for i in bank[tag].size():order.append(i)
		for i in range(order.size()-1,0,-1):
			var j=rng.randi_range(0,i)
			var temp=order[i];order[i]=order[j];order[j]=temp
		if order.size()>1 and order.back()==last_take.get(tag,-1):order.reverse()
	var take:int=order.pop_back()
	orders[tag]=order
	last_take[tag]=take
	return take

func select_strike()->int:return select_take("strike")

func source_point(tag:String,source_key:String="")->Vector3:
	match tag:
		"return","return_short":return machine.paper_grabs.target("Carriage return")
		"platen":return machine.groups.platen.position
		"bell":return Vector3(.115,.852,-1.40)
		"space":return machine.key_grabs.point("Space")
		"backspace":return machine.key_grabs.point("↶")
		"tab":return machine.key_grabs.point("TAB")
		"shift_press","shift_release":return machine.key_grabs.point(source_key if source_key in ["Left shift","Right shift","Shift lock"] else "Left shift")
	return Vector3(0,1.13,-.755)

func _process(_dt):
	if not is_instance_valid(listener) or not listener.is_inside_tree():return
	update_listener()
	for voice in voices:
		if voice.playing:mix_voice(voice)

func mix_voice(voice:AudioStreamPlayer3D):
	var tag:String=voice.get_meta("action")
	voice.position=source_point(tag,voice.get_meta("source_key",""))
	voice.panning_strength=1. if spatial else 0.
	var distance=voice.position.distance_to(listener.position)
	var perspective=clampf(2.5/maxf(distance,1.),.65,1.12) if spatial else 1.
	var group_gain=key_gain if tag in ["strike","space","miss","jam"] else mechanism_gain
	var total=master_gain*group_gain*float(voice.get_meta("gain"))*perspective
	voice.volume_db=linear_to_db(total) if total>.00001 else -100.

func play_action(tag:String,volume:float,power:float,take:=-1,tempo:="normal",trim_db:=0.,source_key:String=""):
	if not bank.has(tag) or volume<=.001 or power<=0. or not is_instance_valid(listener):return
	var voice:AudioStreamPlayer3D=reserved.get(tag)
	if voice==null:
		voice=voices[cursor]
		cursor=(cursor+1)%10
	if take<0 or take>=bank[tag].size():take=select_take(tag)
	var sample:AudioStream=bank[tag][take]
	voice.stream=tempo_bank[sample].get(tempo,sample)
	master_gain=volume
	# Sound Jay's five original backspace strokes have roughly 11 dB more
	# recording headroom than the other service controls. Match at playback.
	if tag=="backspace" and ResourceLoader.exists(sound_directory+"/backspace.wav"):trim_db+=10.5
	voice.set_meta("action",tag)
	voice.set_meta("source_key",source_key)
	voice.set_meta("gain",minf(power,1.35)*db_to_linear(trim_db))
	update_listener()
	mix_voice(voice)
	voice.play()

func stop_all():
	for voice in voices:
		if is_instance_valid(voice):voice.stop()
