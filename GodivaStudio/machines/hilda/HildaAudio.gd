extends "res://MechanismAudio.gd"
## Hilda's six original print strokes use the desk's shared spatial mixer.
const SAMPLE_DIR := "res://machines/hilda/audio"

func _ready():
	sound_directory = SAMPLE_DIR
	rng.randomize()
	for index in range(1, 7):
		strikes.append(load_sample(SAMPLE_DIR + "/strike_%02d.wav" % index))
	bank["strike"] = strikes

func setup(rig):
	bind_machine(rig)

func update_listener():
	listener.global_transform = machine.camera.global_transform

func source_point(_tag:String, _source_key:String="") -> Vector3:
	return machine.PLATEN_CENTER + Vector3(0, 0, machine.PAPER_RADIUS)

func play_strike(event:Dictionary):
	if event.get("miss", false) or event.get("jam", false): return
	var settings:Dictionary = machine.writer.data
	key_gain = float(settings.keys_volume)
	spatial = bool(settings.spatial_audio)
	var take := int(event.get("sound_take", -1))
	if take < 0 or take >= strikes.size():
		take = select_strike()
		event.sound_take = take
	play_action("strike", float(settings.volume), float(event.power), take,
		str(event.get("sound_tempo","")))
