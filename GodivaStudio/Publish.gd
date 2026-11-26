extends RefCounted
static func pdf(path:String,img:Image,postcard:bool)->bool:
	var f=FileAccess.open(path,FileAccess.WRITE)
	if not f:return false
	var jpg=img.save_jpg_to_buffer(.96);var w=432 if postcard else 612;var h=288 if postcard else 792
	var offsets=[0];f.store_string("%PDF-1.4\n")
	var stream="q\n%d 0 0 %d 0 0 cm\n/Sheet Do\nQ\n"%[w,h]
	var bodies=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Count 1 /Kids [3 0 R] >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Resources << /XObject << /Sheet 4 0 R >> >> /Contents 5 0 R >>"%[w,h],"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length %d >>"%[img.get_width(),img.get_height(),jpg.size()],"<< /Length %d >>\nstream\n%sendstream"%[stream.length(),stream]]
	for i in bodies.size():
		offsets.append(f.get_position());f.store_string("%d 0 obj\n%s\n"%[i+1,bodies[i]])
		if i==3:f.store_string("stream\n");f.store_buffer(jpg);f.store_string("\nendstream\n")
		f.store_string("endobj\n")
	var table=f.get_position();f.store_string("xref\n0 6\n0000000000 65535 f \n")
	for i in range(1,6):f.store_string("%010d 00000 n \n"%offsets[i])
	f.store_string("trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n"%table);f.close();return true
static func gif(path:String,frames:Array)->bool:
	if frames.is_empty():return false
	var f=FileAccess.open(path,FileAccess.WRITE)
	if not f:return false
	var w=frames[0].get_width();var h=frames[0].get_height()
	f.store_string("GIF89a");f.store_16(w);f.store_16(h);f.store_buffer(PackedByteArray([247,0,0]))
	for j in 256:f.store_buffer(PackedByteArray([roundi((j>>5)*255./7),roundi(((j>>2)&7)*255./7),(j&3)*85]))
	f.store_buffer(PackedByteArray([33,255,11]));f.store_string("NETSCAPE2.0");f.store_buffer(PackedByteArray([3,1,0,0,0]))
	for im in frames:
		f.store_buffer(PackedByteArray([33,249,4,4,8,0,0,0,44,0,0,0,0]));f.store_16(w);f.store_16(h);f.store_buffer(PackedByteArray([0,8]))
		var rgb:PackedByteArray=im.get_data();var codes=PackedInt32Array([256])
		for i in w*h:
			if i>0 and i%240==0:codes.append(256)
			codes.append((rgb[i*3]&224)|((rgb[i*3+1]>>3)&28)|(rgb[i*3+2]>>6))
		codes.append(257)
		var bytes=PackedByteArray();var bits=0;var acc=0
		for code in codes:
			acc|=code<<bits;bits+=9
			while bits>=8:bytes.append(acc&255);acc>>=8;bits-=8
		if bits:bytes.append(acc)
		for i in range(0,bytes.size(),255):
			var end=mini(i+255,bytes.size());f.store_8(end-i);f.store_buffer(bytes.slice(i,end))
		f.store_8(0)
	f.store_8(59);f.close();return true
