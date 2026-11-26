extends RefCounted
## Rear sheet cross-sections in carriage coordinates (height, depth). Each
## column is sampled by material arc length so a support cannot feed the page.
const STEP=.018
const ARC_END=2.43*.1519
const ENTRY=Vector2(1.13,-.91)+.1519*Vector2(sin(-2.43),cos(-2.43))
const LANES=12
var lip=Vector2(1.415,-1.424)
var ears=Vector2(-.59,.47)
var sections:Array[PackedVector2Array]=[]
var leading:Array[PackedVector2Array]=[]
var obstacles=PackedVector2Array()
var leading_length:=-1.
const EXIT_HEIGHT=1.315*.1519+(1.315-.34)*.0675
const EXIT_POINT=Vector2(1.13,-.91)+(.1519+.0675)*Vector2(sin(1.315),cos(1.315))-.0675*Vector2(sin(.34),cos(.34))


func rebuild(writer,path:PackedVector2Array,span:Vector2,edge:Vector2):
	# Blade paths follow the centre of the stamped metal. The sheet touches its
	# upper, operator-facing side across the broad face and the rounded bead.
	lip=edge+Vector2(.012,.023)
	ears=span
	var tangent=(lip-ENTRY).normalized()
	var curvature=.45 if writer.data.paper=="Postcard" else 1.15
	var contact=PackedVector2Array([lip])
	# Only the blade face above the unsupported page can carry its weight.
	# A folded finger on the back of the casing cannot pull the page downward.
	for station in path:
		var point=station+Vector2(.012,.023)
		var run=point.distance_to(lip)
		if point.x<lip.x+.015 or run<.004 or point.x<free_point(lip,tangent,run,curvature).x-.002:continue
		if point.y>lip.y+.03 and point.x<lip.x:continue
		if point.distance_to(contact[-1])>.002:contact.append(point)
	obstacles=contact
	leading_length=-1.
	var lengths=PackedFloat32Array([0.])
	for i in range(1,contact.size()):
		lengths.append(lengths[-1]+contact[i-1].distance_to(contact[i]))
	var end_axis=tangent
	if contact.size()>1:
		var anchor=contact.size()-2
		while anchor>0 and contact[-1].distance_to(contact[anchor])<.12:anchor-=1
		end_axis=(contact[-1]-contact[anchor]).normalized()
	var max_length=float(writer.dimensions().y)*.025/writer.PITCH
	var previous_full=lip
	var previous_free=lip
	sections.clear()
	for j in LANES+1:sections.append(PackedVector2Array([lip]))
	var segment=1
	for i in range(1,ceili(max_length/STEP)+2):
		var run=i*STEP
		var free=free_point(lip,tangent,run,curvature)
		var full:Vector2
		while segment<lengths.size() and lengths[segment]<run:segment+=1
		if segment==lengths.size():
			full=free_point(contact[-1],end_axis,run-lengths[-1],curvature)
		else:
			var f=inverse_lerp(lengths[segment-1],lengths[segment],run)
			full=contact[segment-1].lerp(contact[segment],f)
		var free_step=(free-previous_free).normalized()
		var full_step=(full-previous_full).normalized()
		for j in LANES+1:
			var angle=free_step.angle_to(full_step)*float(j)/LANES
			sections[j].append(full if j==LANES else sections[j][-1]+free_step.rotated(angle)*STEP)
		previous_free=free
		previous_full=full

func free_point(start:Vector2,dir:Vector2,length:float,curvature:float)->Vector2:
	var angle=atan2(dir.x,-dir.y)
	var end=maxf(-1.48,angle-curvature*length)
	var arc=(angle-end)/curvature
	return start+Vector2(cos(end)-cos(angle),sin(end)-sin(angle))/curvature+Vector2(sin(end),-cos(end))*maxf(0.,length-arc)

func prepare_leading(writer,top:float):
	var length=maxf(0.,top-EXIT_HEIGHT)
	if is_equal_approx(length,leading_length):return
	leading_length=length
	leading.clear()
	for j in LANES+1:leading.append(PackedVector2Array([EXIT_POINT]))
	# A short typed edge stands up after the bail. Under the weight of a
	# longer overhang the emerging leaf bows rearward over the paper table.
	var curvature=(.52 if writer.data.paper=="Postcard" else 1.55)*smoothstep(.12,1.45,length)
	var free_angle=PI*.5-.34
	var full_angle=free_angle
	for i in range(1,ceili(length/STEP)+2):
		var exposed=maxf(0.,length-(i-1)*STEP)
		# Taper bending toward the unloaded leading edge.
		var bend=curvature*STEP*clampf(1.5*exposed/maxf(length,.01),.12,1.5)
		free_angle=maxf(-1.48,free_angle-bend)
		full_angle=maxf(-1.48,full_angle-bend)
		var pos=leading[LANES][-1]
		for obstacle in obstacles:
			var d=obstacle+Vector2(.010,.003)-pos
			if d.y<-.0001 and d.length()<=exposed:
				full_angle=maxf(full_angle,atan2(d.x,-d.y))
		for j in LANES+1:
			var angle=lerpf(free_angle,full_angle,float(j)/LANES)
			leading[j].append(leading[j][-1]+STEP*Vector2(sin(angle),-cos(angle)))

func weight(x:float,width:Vector2)->float:
	# A released or skewed sheet can miss one or both arms. Stock stiffness
	# carries the span between two contacts, then tapers on the outside edges.
	var contacts=Vector2(smoothstep(-.014,.014,minf(ears.x-width.x,width.y-ears.x)),smoothstep(-.014,.014,minf(ears.y-width.x,width.y-ears.y)))
	var strength=maxf(contacts.x*(1.-.36*smoothstep(.12,1.4,absf(x-ears.x))),contacts.y*(1.-.36*smoothstep(.12,1.4,absf(x-ears.y))))
	if x>=ears.x and x<=ears.y:strength=maxf(strength,minf(contacts.x,contacts.y))
	return strength

func point(h:float,x:float,width:Vector2)->Vector2:
	var paths=sections
	var length:float
	if h>=EXIT_HEIGHT:
		paths=leading
		length=h-EXIT_HEIGHT
		if paths.is_empty():return EXIT_POINT
	else:
		length=maxf(0.,-h-ARC_END)
		var entry=ENTRY.distance_to(lip)
		if length<=entry:return ENTRY.lerp(lip,length/entry)
		length-=entry
		if paths.is_empty():return lip+(lip-ENTRY).normalized()*length
	var strength=weight(x,width)
	var lane=clampf(strength*LANES,0.,LANES)
	var j=mini(int(lane),LANES-1)
	var s=clampf(length/STEP,0.,paths[0].size()-1.)
	var i=mini(int(s),paths[0].size()-2)
	var a=paths[j][i].lerp(paths[j][i+1],s-i)
	var b=paths[j+1][i].lerp(paths[j+1][i+1],s-i)
	return a.lerp(b,lane-j)
