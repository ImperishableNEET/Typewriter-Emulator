extends RefCounted

static func run(desk):
	var writer=desk.writer
	var prior=writer.measured_touch.duplicate()
	writer.measured_touch.clear()
	writer.reset()
	writer.data.seed=3711
	writer.data.touch=0.
	writer.service_profile("A",1000)
	var fast=writer.service_profile("L",1065)
	var slow=writer.service_profile("A",1365)
	desk.check(fast.motion_duration<slow.motion_duration and is_equal_approx(fast.force_fraction,slow.force_fraction),"digital cadence changes timing independently of force")
	var measured=writer.service_profile("backspace",1400,.12)
	var sequence=writer.gesture_index
	var duration:float=measured.motion_duration
	writer.refine_profile(measured,.9)
	desk.check(measured.sound_tempo=="quick" and measured.motion_duration<duration and writer.gesture_index==sequence,"late measured speed revises a single gesture")
	desk.check(writer.measured_touch.size()==1 and writer.measured_touch.backspace.x==1.,"only the original measured input trains the fallback")
	var delayed=writer.service_profile("tab",1550)
	writer.refine_profile(delayed,.35)
	writer.refine_profile(delayed,.35)
	desk.check(writer.measured_touch.tab.x==1. and is_equal_approx(writer.measured_touch.tab.y,.35),"late service reading trains once")
	for i in 90:writer.service_profile("backspace",1700+70*i,.2)
	var learned=writer.calibrated_touch("backspace")
	desk.check(writer.measured_touch.backspace.x==64. and learned.x>.2 and learned.x<.35 and learned.y<.18,"bounded sample history learns a light operator with shrinkage")
	desk.check(writer.calibrated_touch("platen").is_equal_approx(Vector2(.56,.18)),"different service mechanisms keep independent calibration")
	writer.measured_touch.clear()
	writer.reset_gesture_history()
	writer.data.touch=1.
	var sum=0.
	var samples=[]
	for i in 128:
		var stroke=writer.service_profile("space",2000+i*130)
		samples.append(stroke.force_fraction)
		sum+=stroke.force_fraction
	var mean=sum/samples.size()
	var variance=0.
	var covariance=0.
	for i in samples.size():
		var centered=samples[i]-mean
		variance+=centered*centered
		if i:covariance+=centered*(samples[i-1]-mean)
	desk.check(variance>0. and covariance>.1*variance and covariance<.95*variance,"successive digital gestures have related, varied effort")
	writer.reset()
	writer.data.touch=0.
	writer.set_touch_regulator(3)
	var first=writer.action("l",100,true,true)
	writer.data.ribbon_pos=3000
	writer.action("a",220,true)
	var bin:String=first.wear_bin
	writer.apply_downstroke(first,4.,first.ribbon_transfer,0.)
	desk.check(first.miss and writer.data.wear[bin]==1.,"late miss removes only its own ribbon contact")
	writer.apply_downstroke(first,85.,first.ribbon_transfer,1.)
	writer.apply_downstroke(first,85.,first.ribbon_transfer,1.)
	desk.check(not first.miss and writer.data.wear[bin]==2.,"refined hit counts once in its original ribbon cell")
	writer.data.ribbon="Stencil"
	var stencil=writer.action("l",420,true,true)
	writer.apply_downstroke(stencil,4.,stencil.ribbon_transfer,0.)
	var slow_risk=writer.jam_probability(65)
	writer.apply_downstroke(stencil,85.,stencil.ribbon_transfer,1.)
	desk.check(not writer.data.wear.has(stencil.wear_bin),"sensor refinement preserves stencil wear")
	desk.check(slow_risk>writer.jam_probability(65) and writer.jam_probability(150)==0.,"previous bar recovery determines the collision window")
	var nominal_results=[]
	var measured_results=[]
	for setting in range(4):
		writer.reset()
		writer.data.touch=0.
		writer.set_touch_regulator(setting)
		var stroke=writer.action("l",100,true,true)
		nominal_results.append(stroke.power)
		desk.check(stroke.key=="L" and not stroke.miss,"normal effort contacts at detent %d" % setting)
		writer.set_touch_regulator((setting+1)%4)
		# The sensor sample can arrive after another lever command. Its strike
		# still belongs to the setting in force at key-down.
		writer.apply_downstroke(stroke,5.2,stroke.ribbon_transfer,.65)
		measured_results.append(stroke.power)
		desk.check(stroke.downstroke_speed==5.2 and stroke.alpha>0 and not stroke.miss,"calibrated analog impact at detent %d" % setting)
		writer.set_touch_regulator(setting)
		var one=writer.action("1",300,true)
		desk.check(one.key=="L" and is_equal_approx(one.power,nominal_results[-1]),"numeral 1 uses the L return spring")
	for setting in range(1,4):
		desk.check(nominal_results[setting]<nominal_results[setting-1],"detent increases spring work at equal simulated input")
		desk.check(measured_results[setting]<measured_results[setting-1],"detent increases spring work at equal calibrated input")
	desk.check(is_equal_approx(nominal_results[1],.96) and is_equal_approx(measured_results[1],lerpf(.30,1.18,.65)),"default detent preserves the previous typing response")
	var path=OS.get_environment("TEMP").path_join("godiva-player-tools").path_join("touch-lever-test.godiva")
	desk.check(writer.save_file(path),"save touch detent")
	writer.reset()
	desk.check(writer.load_file(path) and writer.data.touch_regulator==3,"reload touch detent")
	writer.new_stock("Postcard")
	desk.check(writer.data.touch_regulator==3,"loading stock keeps the lever position")
	var old=JSON.parse_string(FileAccess.get_file_as_string(path))
	old.erase("touch_regulator")
	var file=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(old));file.close()
	desk.check(writer.load_file(path) and writer.data.touch_regulator==1,"old sheets open at the original nominal detent")
	writer.reset()
	desk.sync()
	writer.measured_touch=prior
