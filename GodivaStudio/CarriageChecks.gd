extends RefCounted

static func run(desk):
	var writer=desk.writer
	writer.reset()
	writer.data.left=4
	writer.data.right=12
	writer.move_col(7)
	writer.slide_carriage(9.25)
	desk.check(writer.carriage_column()==7.,"hand travel requires a release button")
	for first in ["left","right"]:
		var second="right" if first=="left" else "left"
		writer.set_carriage_release(first,true)
		writer.slide_carriage(6.25)
		writer.set_carriage_release(second,true)
		writer.set_carriage_release(first,false)
		desk.check(writer.carriage_release_held(second) and not writer.carriage_release_held(first),"independent release buttons")
		desk.check(is_equal_approx(writer.carriage_column(),6.25),"one remaining button keeps the dog out")
		var old_feed=writer.data.ribbon_pos
		var old_line=writer.data.half
		for command in ["H"," ","\b","\n","\t"]:
			writer.action(command,100)
		desk.check(writer.data.events.is_empty() and writer.data.ribbon_pos==old_feed and writer.data.half==old_line and writer.carriage_column()==6.25,"released carriage blocks key actions")
		writer.set_carriage_release(second,false)
		desk.check(not writer.carriage_held() and writer.carriage_column()==7.,"spring catches the next tooth")
	writer.set_carriage_release("right",true)
	writer.slide_carriage(-999)
	desk.check(writer.carriage_column()==writer.rail_left(),"left physical limit")
	writer.slide_carriage(-1.75)
	desk.check(writer.set_flying_margin("left") and writer.data.left==-1 and writer.data.right==12,"capture outward left margin at the landing tooth")
	desk.check(not writer.set_flying_margin("right") and writer.data.right==12,"keep opposing margin independent")
	writer.slide_carriage(999)
	desk.check(writer.carriage_column()==writer.rail_right(),"right physical limit")
	writer.slide_carriage(16.25)
	desk.check(writer.set_flying_margin("right") and writer.data.right==17,"capture outward right margin")
	desk.check(not writer.set_flying_margin("left") and writer.data.left==-1,"prevent inverted left stop")
	var path=OS.get_environment("TEMP").path_join("godiva-player-tools").path_join("carriage-margin-test.godiva")
	desk.check(writer.save_file(path),"save while holding carriage")
	writer.slide_carriage(5)
	desk.check(writer.load_file(path),"restore the dragged carriage")
	desk.check(not writer.carriage_held() and writer.carriage_column()==17. and writer.data.right==17 and writer.data.left==-1,"saved stops and released dog restore")
	writer.action("\n",150)
	desk.check(writer.data.col==-1,"return catches the newly set left margin")
	writer.action("H",200)
	desk.check(writer.data.events.back().col==-1,"ink lands on selected tooth")
	writer.data.tabs=[]
	writer.action("\t",250)
	desk.check(writer.data.col==17,"tab catches the newly set right margin")
	writer.new_stock("Letter")
	desk.check(writer.data.col==-1 and writer.data.left==-1 and writer.data.right==17,"fresh sheets keep the margin stops")
	writer.move_col(23)
	writer.set_flying_margin("right")
	writer.move_col(15)
	writer.set_flying_margin("left")
	var letter_center:int=writer.bank_center_column()
	writer.new_stock("Postcard")
	var offset:int=writer.bank_center_column()-letter_center
	desk.check(writer.data.left==15+offset and writer.data.right==23+offset,"centered postcard keeps stops aligned to the carriage")
	writer.reset()
	desk.sync()
