extends Control
signal picked(event:Dictionary)
var writer
var carbon=false
var rect:=Rect2()
var follow=true
var scroll_y=0.
var archived:ImageTexture

func show_finished(image:Image):
	archived=ImageTexture.create_from_image(image) if image else null
	follow=archived==null
	scroll_y=0.
	queue_redraw()

func _draw():
	if not writer:return
	draw_rect(Rect2(Vector2.ZERO,size),Color("#283931"))
	if not archived and not writer.data.get("sheet_loaded",true):
		rect=Rect2()
		return
	var dims=archived.get_size() if archived else Vector2(writer.dimensions())
	var sc=(size.x-48.)/dims.x
	var extent=dims*sc
	var cy=(writer.BASE+writer.data.half*writer.LEADING*.5)*sc
	var scroll=clampf(cy-size.y*.65,0,maxf(0.,extent.y-size.y+40.)) if follow else scroll_y
	rect=Rect2(Vector2(24,18-scroll),extent)
	draw_rect(Rect2(rect.position+Vector2(4,5),rect.size),Color("#192c24"))
	draw_texture_rect(archived if archived else (writer.carbon_texture if carbon else writer.texture),rect,false)
	if archived:return
	var cell=Vector2(writer.MARGIN+(writer.data.col+.5)*writer.PITCH,writer.BASE+writer.data.half*writer.LEADING*.5+4)
	var p=rect.position+preload("res://PaperGrabs.gd").material_pixel(writer,cell)*sc
	draw_line(p-Vector2(writer.PITCH*.42*sc,0),p+Vector2(writer.PITCH*.42*sc,0),Color("#ac5636"),2)
func _gui_input(e):
	if e is InputEventMouseButton and e.pressed:
		if not archived and e.button_index==MOUSE_BUTTON_LEFT and rect.has_point(e.position):
			var p=(e.position-rect.position)/rect.size*Vector2(writer.dimensions())
			for i in range(writer.data.events.size()-1,-1,-1):
				var hit=writer.data.events[i]
				var r=Rect2(writer.MARGIN+hit.col*writer.PITCH+hit.dx,writer.BASE+hit.half*writer.LEADING*.5+hit.dy-writer.PITCH*1.125,writer.PITCH,writer.PITCH*writer.HF)
				if r.has_point(p):picked.emit(hit);return
		if e.button_index in [MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_UP]:
			if follow:scroll_y=18-rect.position.y
			follow=false;scroll_y=clampf(scroll_y+(48 if e.button_index==MOUSE_BUTTON_WHEEL_DOWN else -48),0,maxf(0,rect.size.y-size.y+40))
			queue_redraw();accept_event()
