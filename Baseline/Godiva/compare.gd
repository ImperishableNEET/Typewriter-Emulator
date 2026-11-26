extends SceneTree
## Compare a candidate package to Godiva's frozen pre-module session.
var failed=false

func _initialize():
	call_deferred("run")

func check_equal(label:String,actual,expected):
	if actual!=expected:
		failed=true
		push_error("%s: expected %s, got %s"%[label,expected,actual])

func fingerprint(image:Image)->String:
	var hash=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()

func run():
	var folder=OS.get_environment("GODIVA_FIXTURE_DIR")
	var expected=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json")))
	change_scene_to_file("res://Desk.tscn")
	for i in 6:await physics_frame
	var desk=current_scene
	var writer=desk.writer
	if not writer.load_file(folder.path_join("writing-session.godiva")):
		push_error("Could not load the legacy Godiva session")
		quit(1)
		return
	desk.browse_page(-1)
	desk.changed()
	check_equal("draft",fingerprint(writer.raster),expected.pixel_sha256.draft)
	check_equal("draft carbon",fingerprint(writer.carbon_page),expected.pixel_sha256.draft_carbon)
	var state={"column":float(writer.data.col),"half_line":float(writer.data.half),
		"ribbon":writer.data.ribbon,"stock":writer.data.paper,
		"finished_count":float(writer.data.finished_pages.size()),"strike_count":float(writer.data.events.size())}
	check_equal("mounted draft state",state,expected.mounted_state)
	for i in writer.data.finished_pages.size():
		for carbon in [false,true]:
			desk.paper.carbon=carbon
			desk.browse_page(i)
			var key="page_%d%s"%[i+1,"_carbon" if carbon else ""]
			check_equal(key,fingerprint(desk.output_image()),expected.pixel_sha256.get(key))
	desk.browse_page(-1)
	writer.reset()
	writer.data.seed=30001958
	writer.data.carbon=true
	var input="l1-/ ^e\bH"
	for i in input.length():
		writer.action(input[i],1000+110*i,false,false,.8,true)
	var physical=[]
	for event in writer.data.events:
		physical.append([event.key,event.glyph])
	check_equal("new physical key and printed face",physical,expected.fresh_keys)
	check_equal("new impressions",fingerprint(writer.raster),expected.pixel_sha256.fresh_typing)
	if not failed:print("GODIVA_BASELINE_MATCH")
	desk.mechanism_audio.stop_all()
	unload_current_scene()
	await process_frame
	quit(1 if failed else 0)
