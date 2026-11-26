extends RefCounted
## Gesture speed in the control's physical units per second near actuation.
const WINDOW=.080
var origin_usec:int
var samples:Array[Vector2]=[]

func reset(position:float):
	origin_usec=Time.get_ticks_usec()
	samples.assign([Vector2(0.,position)])

func record(position:float):
	var now=(Time.get_ticks_usec()-origin_usec)*.000001
	while samples.size()>1 and samples[1].x<=now-WINDOW:
		samples.pop_front()
	samples.append(Vector2(now,position))

func speed()->float:
	if samples.size()<2:return 0.
	var last=samples.back()
	var first=samples.front()
	var cutoff:float=last.x-WINDOW
	if first.x<cutoff:
		var second=samples[1]
		var fraction=inverse_lerp(first.x,second.x,cutoff)
		first=Vector2(cutoff,lerpf(first.y,second.y,fraction))
	return (last.y-first.y)/maxf(.006,last.x-first.x)
