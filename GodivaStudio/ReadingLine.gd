extends Control
var writer
var carbon_view=false
var sample:Texture2D
var caption=""
func show_strike(event:Dictionary,hit:bool):
	var e=event.duplicate();e.col=0;e.half=0
	var a=Image.create(42,40,false,Image.FORMAT_RGBA8);a.fill(Color("#f5f0df"))
	if hit and not e.jam and not e.miss:
		var mask=writer.mask(e.glyph,2);var pos=Vector2i(7,0)
		for y in mini(mask.get_height(),40):
			for x in mask.get_width():
				var ink=Color("#8d2927") if e.ink=="Red" or (e.ink=="Split" and y>mask.get_height()*.44) else Color("#242420")
				if e.ink!="Stencil":a.set_pixelv(pos+Vector2i(x,y),Color("#f5f0df").lerp(ink,mask.get_pixel(x,y).a*e.alpha))
	sample=ImageTexture.create_from_image(a)
	caption="Replay   ·   "+str(e.key)+"   ·   "+str(e.ink)+" ribbon";queue_redraw()
func _draw():
	if not writer or size.x<1:return
	if sample:
		draw_rect(Rect2(Vector2.ZERO,size),Color("#f5f0df"));draw_texture_rect(sample,Rect2(12,0,70,size.y),false)
		draw_string(ThemeDB.fallback_font,Vector2(94,size.y*.58),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("#35493d"));return
	var d=writer.data;var tex=writer.carbon_texture if carbon_view else writer.texture
	draw_rect(Rect2(Vector2.ZERO,size),Color("#efe9d7"))
	var scale_factor=1.8
	var width=size.x/scale_factor
	var center=Vector2(writer.MARGIN+(d.col+.5)*writer.PITCH,writer.BASE+float(d.half)*writer.LEADING*.5-4)
	center=preload("res://PaperGrabs.gd").material_pixel(writer,center)
	var x=clampf(center.x-width*.68,0,maxf(0,tex.get_width()-width))
	var height=size.y/scale_factor;var y=clampf(center.y-height*.52,0,maxf(0,tex.get_height()-height))
	draw_texture_rect_region(tex,Rect2(Vector2.ZERO,size),Rect2(x,y,width,height))
	var px=(center.x-x)*scale_factor;var py=(center.y+9-y)*scale_factor
	draw_line(Vector2(px-7,py),Vector2(px+7,py),Color("#a45e3f"),1.6)

