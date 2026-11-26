extends RefCounted
## A normal click acts immediately. A platform-recognized double-click retracts
## only its first click, then delegates to the part's own reset.
var first_hit: Dictionary = {}
var first_position := Vector2.ZERO
var held := false
var released := false
var consume_release := false
var sheet: WeakRef
var before: Dictionary
var after: Dictionary

func forget():
	first_hit = {}
	before = {}
	after = {}
	sheet = null
	held = false
	released = false

func eligible(m,hit:Dictionary) -> bool:
	if hit.is_empty():return false
	var label:String=hit.label
	var owner=hit.get("owner")
	if owner==m.page_stack:return false
	if owner==m.action_grabs:
		if label==owner.GUIDE:return true
		return m.writer.data.jammed and owner.paths[label].key in m.key_grabs.jam_keys
	if owner==m.key_grabs:
		if label.begins_with(owner.SLUG):
			return m.writer.data.jammed and label.trim_prefix(owner.SLUG) in owner.jam_keys
		return label in ["Left shift","Right shift","Shift lock","⇄","Touch regulator",owner.RIBBON_LEVER] or label.begins_with("Ribbon index ") or label.begins_with("Ribbon guide ")
	return true

func state(m) -> Dictionary:
	var w=m.writer
	var values:Dictionary=w.data.duplicate()
	# Printable keycaps and healthy type actions always take both clicks. None
	# of the resettable controls edits the impressions, tab bank or ribbon wear.
	for field in ["tabs","wear","events","finished_pages"]:values.erase(field)
	return {"settings":values, "count":w.data.events.size(),
		"shift_mouse":m.key_grabs.desk.shift_mouse, "latched":m.key_latched}

func observe(event) -> bool:
	if event is InputEventMouseMotion and held and event.position.distance_to(first_position)>3.:
		forget()
	elif event is InputEventMouseButton:
		if event.button_index!=MOUSE_BUTTON_LEFT:
			forget()
		elif not event.pressed and consume_release:
			consume_release=false
			return true
	return false

func finish(m):
	if not held:return
	held=false
	released=true
	after=state(m)
	if after.count!=before.count:
		forget()

func can_reset(m,event,hit:Dictionary) -> bool:
	if not event.double_click or not released or not sheet or sheet.get_ref()!=m.writer.raster:return false
	if m.writer.data.events.size()!=after.count or not eligible(m,first_hit):return false
	if event.position.distance_to(first_position)>10.:return false
	if hit.get("label","")==first_hit.label:return true
	# A lifting cover, rotating selector or travelling carriage can expose
	# another object under the original click. Re-pick that original pixel.
	var old_pixel:Dictionary=m.choose_grab(first_position)
	return old_pixel.get("label","")!=first_hit.label and old_pixel.get("label","")==hit.get("label","")

func retract(m):
	var w=m.writer
	for key in before.settings:
		if before.settings[key]!=after.settings[key] and w.data[key]==after.settings[key]:
			w.data[key]=before.settings[key]
	if m.key_grabs.desk.shift_mouse==after.shift_mouse:m.key_grabs.desk.shift_mouse=before.shift_mouse
	if m.key_latched==after.latched:m.key_latched=before.latched

func press(m,event,hit:Dictionary) -> bool:
	consume_release=false
	if can_reset(m,event,hit):
		var target=first_hit
		retract(m)
		forget()
		consume_release=true
		m.reset_part(target)
		return true
	forget()
	if eligible(m,hit):
		first_hit=hit
		first_position=event.position
		sheet=weakref(m.writer.raster)
		before=state(m)
		held=true
	return false
