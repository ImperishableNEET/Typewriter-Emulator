extends RefCounted

const HELPER = "res://assets/wooting-touch.bin"
const PUNCTUATION = {
	KEY_MINUS:45, KEY_EQUAL:46, KEY_BRACKETLEFT:47, KEY_BRACKETRIGHT:48,
	KEY_SEMICOLON:51, KEY_APOSTROPHE:52, KEY_QUOTELEFT:53, KEY_COMMA:54,
	KEY_PERIOD:55, KEY_SLASH:56, KEY_KP_DIVIDE:84, KEY_KP_MULTIPLY:85,
	KEY_KP_SUBTRACT:86, KEY_KP_ADD:87, KEY_KP_PERIOD:99,
}
const SERVICE_KEYS = {
	KEY_ENTER:40,KEY_BACKSPACE:42,KEY_TAB:43,KEY_SPACE:44,KEY_BACKSLASH:49,
	KEY_HOME:74,KEY_END:77,KEY_RIGHT:79,KEY_LEFT:80,KEY_DOWN:81,KEY_UP:82,
	KEY_KP_ENTER:88,
}
var child:Dictionary = {}
var samples:Array = []
var status := "Simulated touch"
var connected := false
var anchors:Array = []
var shift_positions:=Vector2(-1.,-1.)
var shift_release_ms:=[-1,-1]
var service_positions:Dictionary={}
var service_release_ms:Dictionary={}
var print_positions:Dictionary={}

func shift_depth(side:int)->float:
	var depth=shift_positions[side]
	if depth==0. and Time.get_ticks_msec()>shift_release_ms[side]:return -1.
	return depth if connected else -1.

static func key_for_hid(hid:int)->int:
	if hid>=4 and hid<=29:return KEY_A+hid-4
	if hid>=30 and hid<=38:return KEY_1+hid-30
	if hid==39:return KEY_0
	if hid>=89 and hid<=97:return KEY_KP_1+hid-89
	if hid==98:return KEY_KP_0
	var key=PUNCTUATION.find_key(hid)
	return int(key) if key!=null else KEY_NONE

func service_depth(hid:int)->float:
	if not connected:return -1.
	var depth:float=service_positions.get(hid,-1.)
	if depth==0. and Time.get_ticks_msec()>service_release_ms.get(hid,-1):return -1.
	return depth

static func valid_curve(points:Variant)->bool:
	if not points is Array or points.size()!=4:return false
	var previous:=0.
	for value in points:
		if typeof(value) not in [TYPE_FLOAT,TYPE_INT]:return false
		if not is_finite(value) or value<=0. or value<previous*1.05:return false
		previous=value
	return points[3]>=points[0]*1.5

func touch_fraction(speed:float)->float:
	if anchors.is_empty():return clampf(log(maxf(speed,4.)/4.)/log(30.),0.,1.)
	for i in range(1,4):
		if speed<=anchors[i]:
			var t=clampf(inverse_lerp(log(anchors[i-1]),log(anchors[i]),log(maxf(speed,.0001))),0.,1.)
			return (i-1+t)/3.
	return 1.

static func hid_for(key:int,location:int=KEY_LOCATION_UNSPECIFIED)->int:
	if key >= KEY_A and key <= KEY_Z:return 4 + key - KEY_A
	if key >= KEY_1 and key <= KEY_9:return 30 + key - KEY_1
	if key == KEY_0:return 39
	if key >= KEY_KP_1 and key <= KEY_KP_9:return 89 + key - KEY_KP_1
	if key == KEY_KP_0:return 98
	if key == KEY_SHIFT:return 229 if location==KEY_LOCATION_RIGHT else 225
	if SERVICE_KEYS.has(key):return SERVICE_KEYS[key]
	return PUNCTUATION.get(key,0)

func stop():
	if not child.is_empty() and OS.is_process_running(child.pid):OS.kill(child.pid)
	child.clear()
	connected=false
	shift_positions=Vector2(-1.,-1.)
	service_positions.clear()
	service_release_ms.clear()
	print_positions.clear()
	shift_release_ms=[-1,-1]
	samples.clear()
	status="Simulated touch"

func start():
	stop()
	if OS.get_name()!="Windows":
		status="Wooting input requires Windows"
		return
	var bytes=FileAccess.get_file_as_bytes(HELPER) if FileAccess.file_exists(HELPER) else PackedByteArray()
	if bytes.is_empty():
		status="Wooting reader missing · simulated touch"
		return
	# Give each instance its own executable so concurrent writing rooms can run.
	var path=ProjectSettings.globalize_path("user://wooting-touch-%d.exe" % OS.get_process_id())
	var file=FileAccess.open(path,FileAccess.WRITE)
	if file==null:
		status="Cannot start Wooting reader · simulated touch"
		return
	file.store_buffer(bytes)
	file.close()
	child=OS.execute_with_pipe(path,[str(OS.get_process_id())],false)
	status="Looking for keyboard…" if not child.is_empty() else "Reader unavailable · simulated touch"

func clean_up():
	stop()
	var path="user://wooting-touch-%d.exe" % OS.get_process_id()
	if FileAccess.file_exists(path):DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func poll():
	if child.is_empty():return
	if not OS.is_process_running(child.pid):
		var code=OS.get_process_exit_code(child.pid)
		stop()
		status="Install the Wooting Analog SDK · simulated touch" if code==2 else "Reader unavailable · simulated touch"
		return
	var pipe:FileAccess=child.stdio
	var available=int(pipe.get_length()/16)*16
	if available == 0:return
	var bytes=pipe.get_buffer(available)
	var now=Time.get_unix_time_from_system()*1000.
	for i in range(0,bytes.size()-15,16):
		var hid=bytes.decode_u32(i)
		var speed=bytes.decode_float(i+4)
		var stamp=bytes.decode_double(i+8)
		if hid==0:
			connected=speed>0
			status="Wooting connected" if connected else "Waiting for keyboard · simulated touch"
			if not connected:
				samples.clear()
				shift_positions=Vector2(-1.,-1.)
				service_positions.clear()
				service_release_ms.clear()
				print_positions.clear()
				shift_release_ms=[-1,-1]
		elif hid in [0x100e1,0x100e5]:
			var side=int(hid==0x100e5)
			if speed==0. and shift_positions[side]>0.:shift_release_ms[side]=Time.get_ticks_msec()+95
			shift_positions[side]=clampf(speed,-1.,1.) if connected else -1.
		elif hid in [0x1002a,0x1002b,0x1002c]:
			var usage=hid & 0xffff
			if speed==0. and service_positions.get(usage,-1.)>0.:
				service_release_ms[usage]=Time.get_ticks_msec()+250
			service_positions[usage]=clampf(speed,-1.,1.)
		elif hid & 0x10000:
			var usage=hid & 0xffff
			if connected and speed>0.:print_positions[usage]=clampf(speed,0.,1.)
			else:print_positions.erase(usage)
		elif connected and stamp>=now-350.:
			samples.append([hid,stamp,speed])
	while not samples.is_empty() and samples.front()[1]<now-350.:samples.pop_front()

func take_speed(hid:int,pressed_ms:float)->float:
	poll()
	var closest=-1
	var distance=INF
	for i in samples.size():
		var delta:float=samples[i][1]-pressed_ms
		if samples[i][0]==hid and delta>=-65. and delta<=40. and absf(delta)<distance:
			closest=i
			distance=absf(delta)
	if closest<0:return -1.
	var sample=samples.pop_at(closest)
	return sample[2]
