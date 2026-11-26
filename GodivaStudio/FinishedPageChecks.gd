extends RefCounted

static func same_pixels(image:Image,original:Image)->bool:
	return image!=null and image.get_size()==original.get_size() and image.get_format()==original.get_format() and image.get_data()==original.get_data()

static func reader_matches(desk,index:int,expected:Image):
	var model_ok:bool=desk.viewed_page==index and desk.paper.archived!=null
	desk.check(model_ok and same_pixels(desk.output_image(),expected),"reader outputs the exact selected sheet")
	if model_ok and DisplayServer.get_name()!="headless":
		desk.check(same_pixels(desk.paper.archived.get_image(),expected),"reader texture displays the selected sheet")

static func run(desk):
	var w=desk.writer
	var original_path:String=desk.save_path
	var original_task:String=desk.file_task
	var originals:Array[Image]=[]
	var carbons:Array[Image]=[]
	var stocks=["Letter","Postcard","Letter"]
	var inks=["Black","Red","Split"]
	var lines=["Godiva","Two","Three"]
	w.reset("Letter")
	desk.paper.carbon=false
	desk.browse_page(-1)
	for i in lines.size():
		if i>0:
			desk.load_next_sheet(stocks[i])
		w.data.carbon=true
		w.data.ribbon=inks[i]
		for ch in lines[i]:
			desk.type_char(ch,0,.8,true)
		# Two typebar strikes share a physical cell, with different ribbon colours.
		desk.type_char("\b")
		var before_overstrike:Image=w.raster.duplicate()
		w.data.ribbon=inks[(i+1)%inks.size()]
		desk.type_char("X",0,.8,true)
		var events:Array=w.data.events
		desk.check(events.size()==lines[i].length()+1 and events[-1].col==events[-2].col and events[-1].ink!=events[-2].ink,"archive fixture includes mixed ribbon and an overstrike")
		desk.check(not same_pixels(w.raster,before_overstrike),"overstrike changed the live raster")
		var original:Image=w.raster.duplicate()
		var carbon:Image=w.carbon_page.duplicate()
		var region=Rect2i(w.MARGIN-3,w.BASE-26,w.PITCH*(lines[i].length()+1),36)
		var blank=Image.create(region.size.x,region.size.y,false,Image.FORMAT_RGBA8)
		blank.fill(Color("#e3e8dc"))
		desk.check(not same_pixels(carbon.get_region(region),blank),"recorded carbon impressions are present")
		originals.append(original)
		carbons.append(carbon)
		desk.check(desk.finish_page(),"printed sheet comes out of the platen")
		desk.check(not w.data.sheet_loaded and w.data.finished_pages.size()==i+1,"finishing places one physical sheet on the stack")
		desk.check(w.data.finished_pages[i].paper==stocks[i] and original.get_size()==w.stock_dimensions(stocks[i]),"finished sheet preserves its original paper stock and size")
		reader_matches(desk,i,original)
		desk.check(not desk.type_char("z") and not desk.finish_page() and w.data.finished_pages.size()==i+1,"an unloaded platen cannot print or eject the same sheet twice")
	desk.load_next_sheet("Letter")
	for ch in "Draft":
		desk.type_char(ch,0,.8,true)
	var draft:Image=w.raster.duplicate()
	var draft_col:int=w.data.col
	var draft_count:int=w.data.events.size()
	desk.previous_page.pressed.emit()
	reader_matches(desk,2,originals[2])
	desk.previous_page.pressed.emit()
	reader_matches(desk,1,originals[1])
	desk.next_page.pressed.emit()
	reader_matches(desk,2,originals[2])
	desk.check(not desk.type_char("z") and same_pixels(w.raster,draft) and w.data.col==draft_col,"browsing the stack preserves the live writing position and impression")
	desk.draft_button.pressed.emit()
	desk.check(desk.viewed_page==-1 and desk.paper.archived==null and w.data.events.size()==draft_count,"back to draft restores the mounted sheet")
	# Use a unique test document and the same save/open callbacks as the file dialog.
	var path="user://finished-pages-check-%d.godiva"%Time.get_ticks_usec()
	desk.file_task="Save"
	desk.file_chosen(path)
	desk.check(FileAccess.file_exists(path),"finished stack saves with the mounted draft")
	w.reset("Postcard")
	desk.file_task="Open"
	desk.file_chosen(path)
	desk.check(w.data.finished_pages.size()==3 and w.data.sheet_loaded and w.data.col==draft_col and same_pixels(w.raster,draft),"reopening restores all three sheets and the live draft")
	if w.data.finished_pages.size()==3:
		for i in [2,0,1]:
			desk.paper.carbon=false
			desk.browse_page(i)
			reader_matches(desk,i,originals[i])
			desk.paper.carbon=true
			desk.browse_page(i)
			reader_matches(desk,i,carbons[i])
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	desk.paper.carbon=false
	w.reset()
	desk.browse_page(-1)
	desk.save_path=original_path
	desk.file_task=original_task
