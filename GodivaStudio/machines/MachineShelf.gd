extends RefCounted
## The desk keeps a mounted draft per machine. Finished sheets travel as frozen images.
const DESKS = {
	"godiva": ["Godiva · Hermes 3000", "res://Desk.tscn", "res://machines/godiva/Godiva.tres"],
	"hilda": ["Hilda · Olympia SM9 De Luxe", "res://machines/hilda/HildaDesk.tscn", "res://machines/hilda/Hilda.tres"],
}

static func selector(parent:Control, active:String, change:Callable) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "Machines ▾"
	menu.tooltip_text = "Switch typewriters and keep each mounted draft"
	menu.focus_mode = Control.FOCUS_NONE
	parent.add_child(menu)
	var ids := DESKS.keys()
	for index in ids.size():
		menu.get_popup().add_radio_check_item(DESKS[ids[index]][0], index)
		menu.get_popup().set_item_checked(index, ids[index] == active)
	menu.get_popup().id_pressed.connect(func(index):
		if ids[index] != active: change.call(ids[index]))
	return menu

static func switch_to(desk:Control, writer, target:String) -> Error:
	if not DESKS.has(target): return ERR_INVALID_PARAMETER
	if not writer.save_file(writer.machine_profile.autosave_path): return ERR_CANT_CREATE
	return desk.get_tree().change_scene_to_file(DESKS[target][1])

static func page_identity(page:Dictionary) -> String:
	if page.has("page_id"): return str(page.page_id)
	return "%s/%d/%s/%s" % [page.get("machine_id","godiva"), int(page.finished_at),
		page.impression_png.sha256_text(), page.carbon_png.sha256_text()]

static func collect_pages(writer):
	for id in DESKS:
		if id == writer.machine_profile.id: continue
		var peer = load(DESKS[id][2])
		if peer == null or not FileAccess.file_exists(peer.autosave_path): continue
		var saved = JSON.parse_string(FileAccess.get_file_as_string(peer.autosave_path))
		if not saved is Dictionary or saved.get("machine_id","godiva") != id: continue
		var pages = saved.get("finished_pages", [])
		if not pages is Array: continue
		var existing := {}
		for page in writer.data.finished_pages:
			var identity := page_identity(page)
			existing[identity] = existing.get(identity,0) + 1
		for page in pages:
			if not page is Dictionary or page.get("machine_id","godiva") != id: continue
			if not writer.valid_finished_page(page): continue
			var identity := page_identity(page)
			if existing.get(identity,0) > 0:
				existing[identity] -= 1
				continue
			page.machine_id = id
			writer.data.finished_pages.append(page)
