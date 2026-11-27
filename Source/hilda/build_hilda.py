"""Build Hilda's editable Olympia SM9 and Godot model from the owner photo study.

Run Blender in background with --factory-startup --python-exit-code 1 --python this_file.
Dimensions are relative. The owner's exterior images establish proportions; linkage
pivots and the shift travel are working approximations. See References/Hilda/README.md.
"""
from pathlib import Path
import json
import math
import os
import tempfile

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "GodivaStudio/machines/hilda"
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 60


def material(name, rgb, metal=0, rough=.4):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    for prop, value in (("Base Color", (*rgb, 1)), ("Metallic", metal), ("Roughness", rough)):
        p.inputs[prop].default_value = value
    return m


enamel = material("Olympia • warm ivory enamel", (.70,.64,.49), .16,.31)
base = material("Olympia • textured basalt chassis", (.17,.16,.14), .32,.54)
ivory = material("Olympia • cream keytop", (.82,.775,.638), .02,.32)
sage = material("Olympia • sea green controls", (.34,.49,.375), .05,.31)
steel = material("Olympia • bright steel", (.61,.62,.60), .82,.25)
barsteel = material("Olympia • typebar steel", (.38,.375,.34), .70,.32)
dark = material("Olympia • phosphated iron", (.053,.054,.051), .65,.39)
rubber = material("Olympia • platen rubber", (.032,.030,.028), .03,.74)
black = material("Olympia • black legends", (.013,.013,.012), .03,.44)
red = material("Olympia • red silk", (.32,.022,.029), .0,.82)
ribbonblack = material("Olympia • black silk", (.028,.019,.025), .0,.82)
teal = material("Olympia • segment medallion", (.112,.18,.18), .24,.46)
blue = material("Olympia • selector blue", (.017,.044,.14))


def pivot(name, xyz=(0,0,0), parent=None):
    obj = bpy.data.objects.new(name, None)
    scene.collection.objects.link(obj)
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = .06
    obj.location = xyz
    if parent:
        # All geometry below is authored at rest in machine coordinates.
        obj.parent = parent
        obj.location = Vector(xyz) - world_origin(parent)
    return obj


def world_origin(obj):
    return obj.location + world_origin(obj.parent) if obj.parent else obj.location.copy()


def mesh(name, verts, faces, mat, parent):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    obj.parent = parent
    obj.location = -world_origin(parent)
    return obj


def soften(obj, amount, steps=3):
    if amount:
        m = obj.modifiers.new("Rolled edges", 'BEVEL')
        m.width, m.segments = amount, steps
        m = obj.modifiers.new("Face normals", 'WEIGHTED_NORMAL')
        m.keep_sharp = True
    return obj


def skin(name, rings, mat, parent, bevel=0):
    n = len(rings[0])
    faces = [tuple(range(n-1,-1,-1))]
    for k in range(len(rings)-1):
        for i in range(n):
            a, b = n*k+i, n*k+(i+1)%n
            faces.append((a,b,b+n,a+n))
    faces.append(tuple(range(n*(len(rings)-1),n*len(rings))))
    return soften(mesh(name,[v for ring in rings for v in ring],faces,mat,parent),bevel)


def box(name, loc, dims, mat, parent, bevel=.008):
    x,y,z = loc
    a,b,c = (v/2 for v in dims)
    return skin(name,[[(x+i*a,y+j*b,z+k*c) for i,j in ((-1,-1),(1,-1),(1,1),(-1,1))]
                      for k in (-1,1)],mat,parent,bevel)


def rod(name, a, b, r, mat, parent, n=12):
    a,b = Vector(a),Vector(b)
    ax = (b-a).normalized()
    v = ax.cross(Vector((0,0,1)) if abs(ax.z)<.9 else Vector((0,1,0))).normalized()
    w = ax.cross(v)
    rings = [[center + r*(v*math.cos(i*math.tau/n)+w*math.sin(i*math.tau/n))
              for i in range(n)] for center in (a,b)]
    ob=skin(name,rings,mat,parent)
    for p in ob.data.polygons[1:-1]:
        p.use_smooth=True
    return ob


def pin_wire(name,start,end,radius):
    # Unit-length geometry also gives the desktop solver an unambiguous local
    # axis. Blender's constraints keep the wire seated during manual posing.
    wire=rod(name,(0,0,0),(0,1,0),radius,steel,frame,8)
    follow=wire.constraints.new('COPY_LOCATION')
    follow.target=start
    stretch=wire.constraints.new('STRETCH_TO')
    stretch.target=end
    stretch.rest_length=1.
    stretch.volume='NO_VOLUME'
    return wire


def text(name, label, loc, size, mat, parent, tilt=0, font=None):
    curve=bpy.data.curves.new(name,'FONT')
    curve.body,curve.size,curve.align_x,curve.align_y=label,size,'CENTER','CENTER'
    curve.resolution_u=4
    if font:
        curve.font=font
    ob=bpy.data.objects.new(name,curve)
    scene.collection.objects.link(ob)
    data=bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    bpy.data.objects.remove(ob,do_unlink=True)
    ob=bpy.data.objects.new(name,data)
    scene.collection.objects.link(ob)
    ob.data.materials.append(mat)
    ob.parent=parent
    ob.location=Vector(loc)-world_origin(parent)
    ob.rotation_euler.x=tilt
    return ob


frame=pivot("HildaFrame")
cover=pivot("HildaRibbonCover",parent=frame)
car=pivot("HildaCarriage",parent=frame)
basket=pivot("HildaShiftBasket",parent=frame)

# Owner photos 01, 02 and 12: a thin shell lip follows the deeper rising base.
for side in (-1,1):
    name="Left" if side<0 else "Right"
    profile=[(-1.58,.14),(-1.58,.25),(-.9,.38),(-.30,.54),
             (.70,.68),(1.08,.58),(1.43,.69),(1.47,.53),(1.32,.13)]
    rings=[[(x,y,z) for y,z in reversed(profile)] for x in sorted((side*1.51,side*1.66))]
    skin(name+" lower casting",rings,base,frame,.033)
    for y in (-1.13,1.10):
        rod(name+" rubber foot",(side*1.34,y,.045),(side*1.34,y,.15),.12,rubber,frame,20)
box("Lower keyboard well",(0,-.58,.18),(3.12,1.99,.09),dark,frame,.045)
def rear_profile(name,points,y,depth,mat,parent,edge=.008):
    # Counterclockwise at the back; outward face normal points toward +Y.
    return skin(name,[[(x,k,z) for x,z in points] for k in (y-depth,y)],mat,parent,edge)


def cut(opening,cutter):
    boolean=opening.modifiers.new("Through opening",'BOOLEAN')
    boolean.operation='DIFFERENCE'
    boolean.object=cutter
    bpy.context.view_layer.objects.active=opening
    bpy.ops.object.modifier_apply(modifier=boolean.name)
    bpy.data.objects.remove(cutter,do_unlink=True)


# The straight-on rear photograph establishes the two removable end pieces,
# rectangular lower openings, notched paper table and screw arrangement.
rear=rear_profile("Removable central rear casting",
                  [(-1.285,.114),(-1.46,.749),(1.46,.749),(1.285,.114)],
                  1.445,.16,base,frame,.022)
for s in (-1,1):
    points=[(s*1.475,.749),(s*1.65,.73),(s*1.49,.113),(s*1.303,.113)]
    rear_profile("Rear casting side seam",points if s==1 else points[::-1],1.443,.16,base,frame,.018)
    cut(rear,box("recess cutter",(s*1.085,1.40,.179),(.145,.27,.054),black,frame,0))
    box("Inner darkness of rear opening",(s*1.085,1.30,.179),(.164,.016,.072),rubber,frame,.003)
box("Metal identification plate",(0,1.451,.446),(.854,.019,.141),steel,frame,.009)


def rear_text(name,label,x,y,z,size,mat,parent):
    o=text(name,label,(x,y,z),size,mat,parent,math.pi/2)
    o.rotation_euler.z=math.pi
    return o


for xx,rows in ((.207,("OLYMPIA WERKE AG","WILHELMSHAVEN","Made in Western Germany")),
                 (-.20,("Inter-Continental Trading Corporation","90 West Street","NEW YORK 6, N.Y."))):
    for i,label in enumerate(rows):
        rear_text("Maker plate "+label,label,xx,1.461,.481-i*.034,
                  .028 if len(label)<19 else .018,black,frame)
for x in (-.40,.40):
    rod("Plate rivet",(x,1.459,.446),(x,1.467,.446),.011,ivory,frame,16)
outline_mat=material("Worn foil lettering",(.40,.39,.32),.38)
for z in (.203,.251):
    box("Trademark outline",(-.575,1.448,z),(.672,.003,.003),outline_mat,frame,.001)
for x in (-.911,-.239):
    box("Trademark outline",(x,1.448,.227),(.003,.003,.047),outline_mat,frame,.001)
rear_text("US trademark","OLYMPIA REG. U.S. PAT. OFF.",-.575,1.451,.226,.040,outline_mat,frame)
paper_back=rear_profile("Notched ivory carriage rear",[
    (-1.48,.808),(-1.48,1.222),(-.087,1.222),(-.087,1.158),
    (1.48,1.158),(1.48,.808)],1.419,.09,enamel,car,.009)
box("Inside of support recess",(.70,1.355,1.179),(1.55,.034,.061),dark,car,.008)
for s in (-1,1):
    xx=s*1.42
    cut(paper_back,rod("Drill",(xx,1.30,.933),(xx,1.48,.933),.035,dark,car,28))
    box("Backing behind bore",(xx,1.306,.933),(.10,.01,.10),dark,car)
    box("Polished carriage end cap",(s*1.545,1.366,1.014),(.145,.116,.417),steel,car,.022)
    for x,z in ((s*.117,1.019),(s*1.548,.938)):
        rod("Carriage slotted fastener",(x,1.410,z),(x,1.434,z),.035,barsteel,car,24)
        slot=box("Screwdriver slot",(x,1.435,z),(.047,.003,.007),dark,car,0)
        for vert in slot.data.vertices:
            dx,dz=vert.co.x-x,vert.co.z-z
            angle=1.54 if s<0 else .48
            vert.co.x=x+dx*math.cos(angle)-dz*math.sin(angle)
            vert.co.z=z+dx*math.sin(angle)+dz*math.cos(angle)
# Owner photo 20261126_004939: two telescoping bright metal sections.
# The outer channel returns around the edges of the narrower graduated slide.
mount_y, mount_z = 1.382, 1.22
rod("Paper rest hinge barrel",(0,mount_y-.034,mount_z),(0,mount_y+.032,mount_z),.046,barsteel,car,32)
support=pivot("HildaPaperSupport",(0,mount_y,mount_z),car)
slide=pivot("HildaPaperSupportSlide",(0,mount_y,mount_z+1.16),support)

def rest_channel(name,width,depth,length,start,parent):
    half=width/2
    wall=.004
    lip=.012
    profile=[(-half,depth),(-half,0),(-half+lip,0),(-half+lip,wall),
             (-half+wall,wall),(-half+wall,depth-wall),(half-wall,depth-wall),
             (half-wall,wall),(half-lip,wall),(half-lip,0),(half,0),(half,depth)]
    rings=[[(x,mount_y+y,mount_z+z) for x,y in profile] for z in [start,start+length]]
    return skin(name,rings,steel,parent,.0015)

rest_channel("Paper rest rolled outer channel",.154,.035,1.28,0,support)
rest_channel("Paper rest graduated slide",.129,.020,1.27,1.20,slide)
box("Paper rest retaining collar",(0,mount_y+.013,mount_z+1.257),(.159,.044,.030),steel,support,.004)
box("Paper rest scale enamel",(0,mount_y+.009,mount_z+1.864),(.080,.008,1.164),ivory,slide,.003)
box("Paper rest folded tip",(0,mount_y+.009,mount_z+2.459),(.108,.026,.022),steel,slide,.003)
for i in range(1,21):
    z=mount_z+2.412-(i-1)*.058
    if i in (1,5,10,15,20):
        text("Paper rest numeral "+str(i),str(i),(0,mount_y+.004,z),.029,black,slide,math.pi/2)
        for side in (-1,1):
            box("Paper rest numbered tick",(side*.031,mount_y+.004,z),(.013,.002,.0035),black,slide,0)
    else:
        box("Paper rest line graduation",(0,mount_y+.004,z),(.037,.002,.0035),black,slide,0)
box("Front fascia",(0,-1.525,.225),(3.28,.12,.13),base,frame,.040)
# A single folded cover. Sections wrap from the keyboard and typebasket openings
# over the radiused outside shoulders to the seam with the basalt casting.
# The front and rear corners also turn in plan. Photo 03 distinguishes the
# long concave keyboard slope from the short convex roll into the flat deck.
stations=[
    # y, crown z, half-width, inner edge x, bridge across the centre
    (-1.581,.277,1.585,1.41,True),(-1.577,.298,1.607,1.41,True),
    (-1.564,.313,1.627,1.41,True),(-1.542,.324,1.643,1.41,True),
    (-1.515,.334,1.652,1.41,True),(-1.467,.350,1.655,1.41,True),
    (-1.459,.352,1.655,1.444,False),(-1.443,.358,1.655,1.467,False),
    (-1.421,.366,1.655,1.480,False),(-1.39,.376,1.655,1.484,False),
    (-1.15,.462,1.655,1.484,False),(-.94,.541,1.655,1.484,False),
    (-.77,.611,1.655,1.484,False),(-.63,.683,1.655,1.484,False),
    (-.52,.752,1.655,1.484,False),(-.447,.815,1.655,1.484,False),
    (-.401,.870,1.655,1.484,False),(-.380,.906,1.655,1.480,False),
    (-.366,.940,1.655,1.468,True),(-.352,.979,1.655,1.455,True),
    (-.337,1.019,1.655,1.45,True),(-.323,1.048,1.655,1.45,True),
    (-.306,1.065,1.655,1.45,True),(-.283,1.073,1.655,1.45,True),
    (-.238,1.077,1.655,1.45,True),(-.143,1.081,1.655,.869,True),
    (-.139,1.081,1.655,.895,False),(-.127,1.082,1.655,.913,False),
    (-.107,1.083,1.655,.921,False),(-.083,1.084,1.655,.914,False),
    (.62,1.106,1.655,.405,False),(.663,1.107,1.655,.390,False),
    (.695,1.108,1.650,.390,False),(.724,1.106,1.637,.396,False),
    (.742,1.097,1.612,.411,False),(.751,1.077,1.583,.428,False)]
vertices,faces,lookup=[],[],{}
def vertex(x,y,z):
    point=(x,y,z)
    if point not in lookup:
        lookup[point]=len(vertices)
        vertices.append(point)
    return lookup[point]
def seam(y):
    for a,b in zip(seam_points,seam_points[1:]):
        if y<=b[0]:
            return a[1]+(b[1]-a[1])*(y-a[0])/(b[0]-a[0])
    return seam_points[-1][1]
seam_points=[(-1.59,.255),(-.9,.386),(-.30,.546),(.70,.686),(.76,.689)]
sections=[]
previous={}
for row,(y,top,width,opening,bridge) in enumerate(stations):
    current={}
    bottom=seam(y)
    rz=min(.061,(top-bottom)*.62)
    for side in (-1,1):
        shoulder=width-.084
        section=[(opening,top),(shoulder,top)]
        for step in range(1,9):
            angle=math.pi*.5*step/8
            section.append((shoulder+.072*math.sin(angle),top-rz*(1-math.cos(angle))))
        section.append((width,bottom))
        strip=[vertex(side*x,y,z) for x,z in section]
        current[side]=strip
        if row:
            prior=previous[side]
            for i in range(len(strip)-1):
                q=(prior[i],prior[i+1],strip[i+1],strip[i])
                faces.append(q if side==1 else q[::-1])
    if row and stations[row-1][4] and row!=19:
        faces.append((previous[-1][0],previous[1][0],current[1][0],current[-1][0]))
    previous=current
    sections.append(current)
# Close each end across the formed shoulder as well as the flat sill.
first,last=sections[0],sections[-1]
faces.append(tuple(first[1][::-1]+first[-1]))
for side in (-1,1):
    cap=last[side]
    x,y,z=vertices[cap[0]]
    lower=vertex(x,y,z-.032)
    corner=vertex(side*(stations[-1][2]-.043),y,z-.032)
    face=tuple(cap+[corner,lower])
    faces.append(face if side==1 else face[::-1])
# Turn the ends of the badge face back into the keyboard opening. Its centre
# is almost upright; the last few centimetres sweep forward into each cheek.
previous_band=None
for i in range(15,19):
    y,z,_,edge,_=stations[i]
    centre_y=-.366+(z-.94)*.275
    offsets=[(-edge,0),(-edge+.007,.36),(-edge+.022,.68),(-edge+.044,.91),
             (-edge+.075,1),(edge-.075,1),(edge-.044,.91),(edge-.022,.68),
             (edge-.007,.36),(edge,0)]
    band=[vertex(x,y+(centre_y-y)*factor,z) for x,factor in offsets]
    if previous_band:
        for j in range(len(band)-1):
            faces.append((previous_band[j],previous_band[j+1],band[j+1],band[j]))
    previous_band=band
faces.append(tuple(previous_band+[sections[19][1][0],sections[19][-1][0]]))
shell=mesh("One-piece rolled ivory cover",vertices,faces,enamel,cover)
for face in shell.data.polygons:
    face.use_smooth=True
gauge=shell.modifiers.new("Formed sheet thickness","SOLIDIFY")
gauge.thickness=.012
gauge.offset=-1
soften(shell,.004,3)
script_path=Path("C:/Windows/Fonts/BRUSHSCI.TTF")
script=bpy.data.fonts.load(str(script_path)) if script_path.exists() else None
text("Raised Olympia script","Olympia",(0,-.389,.873),.151,steel,cover,math.radians(75),script)

# Owner photo 09 shows an exclamation mark above the three-quarters fraction.
rows=[
    [("+","="),('"',"2"),("#","3"),("$","4"),("%","5"),("_","6"),("&","7"),
     ("'","8"),("(","9"),(")","0"),("*","-"),("!","¾"),("TAB",)],
    [("M R",)]+[(v,) for v in "QWERTYUIOP"]+[("¼","½"),("→",)],
    [("",)]+[(v,) for v in "ASDFGHJKL"]+[(":",";"),("@","¢")],
    [("",)]+[(v,) for v in "ZXCVBNM"]+[(",",","),(".","."),("?","/"),("",)]]
shift_pivots={}
printing_keys=[]
part_names=json.loads((APP/"part_names.json").read_text(encoding="utf-8"))
for row,legends in enumerate(rows):
    pitch=.220
    for i,labels in enumerate(legends):
        x=(i-(len(legends)-1)/2)*pitch
        y=-.493-.229*row
        z=.662-.080*row
        w=.184
        p=frame
        capname=f"Key {row+1}-{i+1:02d}"
        is_shift=row==3 and i in (0,len(legends)-1)
        if is_shift:
            side=-1 if i==0 else 1
            x+=.043*side
            w=.256
            p=pivot("HildaLeftShift" if side<0 else "HildaRightShift",(x,.10,.36),frame)
            shift_pivots[side]=p
        elif len(labels)==2 or (len(labels[0])==1 and labels[0].isalpha()):
            lower,upper=(labels[-1],labels[0]) if len(labels)==2 else (labels[0].lower(),labels[0])
            ident=part_names[lower] if len(labels)==2 else upper
            p=pivot(f"Hilda{ident}Key",(x,.10,.36),frame)
            capname=f"Hilda{ident}Keycap"
            printing_keys.append((x,row,ident,lower,upper,p))
        cap=skin(capname,[[(x+u*w*.50,y+v*.102,z) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))],
                          [(x+u*w*.52,y+v*.105,z+.084+.008*v) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))],
                          [(x+u*w*.48,y+v*.097,z+.113+.008*v) for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))]],
                 sage if is_shift else ivory,p,.023)
        rod(capname+" stem",(x,y,z+.013),(x,y+.035,z-.105),.016,steel,p,8)
        rod(capname+" lever",(x,y+.035,z-.105),(x,.10,.36),.011,barsteel,p,8)
        if capname.startswith("Hilda"):
            pickup=Vector((x,.10,.36)).lerp(Vector((x,y+.035,z-.105)),.46)
            pivot("Hilda"+ident+"KeyPin",pickup,p)
        for j,l in enumerate(labels):
            if l:
                offset=(.042-j*.084) if len(labels)==2 else 0
                text(capname+" legend "+str(j),l,(x,y+offset,z+.115+offset*.085),
                     (.084 if len(labels)==2 else (.071 if len(l)>1 else .119)),black,p,.080)
for x,w,s in ((-1.0,.228,"clear"),(0,1.74,""),(1.0,.228,"set")):
    box("Spacebar" if not s else "Tab "+s,(x,-1.37,.354),(w,.187,.125),ivory,frame,.035)
    if s:
        text("Tabulator "+s+" legend",s,(x,-1.369,.418),.068,black,frame)
for i,m in enumerate((blue,ivory,red)):
    marker=box("Ribbon selector index "+str(i),(1.569,-.96-i*.075,.539-i*.028),(.041,.032,.012),m,cover,.004)
    for v in marker.data.vertices:
        v.co.z+=(v.co.y-(-.96-i*.075))*.37

# The photographs establish the radiating bar bank. Slot assignment within it
# is inferred from the lateral key positions and keeps H in the central slot.
def fan_sector(name,rad1,rad2,z,thick,mat):
    n=48
    angles=[-1.09+2.18*i/n for i in range(n+1)]
    def arc(radius,angles):
        return [(radius*math.sin(a),1.018-radius*math.cos(a)) for a in angles]
    xy=arc(rad2,angles)+arc(rad1,reversed(angles))
    return skin(name,[[(x,y,k) for x,y in xy] for k in (z,z+thick)],mat,basket,.009)
fan_sector("Cast smile-shaped typebar rest",1.28,1.335,.692,.045,barsteel)
fan_sector("Segment comb",.48,.698,.72,.041,steel)
fan_sector("De Luxe segment face",.015,.456,.757,.047,teal)
text("De Luxe script","De Luxe",(0,.730,.805),.124,ivory,basket,0,script)
printing_keys.sort(key=lambda entry:(entry[0],entry[1]))
h_slot=next(i for i,entry in enumerate(printing_keys) if entry[2]=="H")
contact_angle=2.54
print_face=Vector((0,.91,1.12))
shaft_height=.72
arm_length=(print_face.z-shaft_height)/math.sin(contact_angle)
shaft_radius=-arm_length*math.cos(contact_angle)
bar_axes=[]
links={}
for i,(key_x,key_row,ident,lower,upper,key_parent) in enumerate(printing_keys):
    span=h_slot if i<h_slot else len(printing_keys)-1-h_slot
    a=(i-h_slot)/span*1.055
    radial=Vector((math.sin(a),-math.cos(a),0))
    tangent=Vector((math.cos(a),math.sin(a),0))
    root=Vector((0,print_face.y,shaft_height))+shaft_radius*radial
    tip=root+arm_length*radial
    p=pivot(f"Hilda{ident}Bar",root,basket)
    bar_axes.append((p,a))
    tag=f"{ident} hammer"
    edge=(.009*math.cos(a),.009*math.sin(a))
    skin(tag+" blade",[[(v[0]+s*edge[0],v[1]+s*edge[1],v[2]+h) for v,s in
                        ((root,-1),(tip,-1),(tip,1),(root,1))] for h in (-.016,.016)],barsteel,p,.004)
    # Every dual-face slug must be square to the platen at impact, including
    # those attached to strongly angled outer bars. Construct at contact,
    # then inverse-rotate the complete head into its soldered resting pose.
    undo_contact=Matrix.Translation(root) @ Matrix.Rotation(contact_angle,4,tangent) @ Matrix.Translation(-root)
    slug=box(f"Hilda{ident}Slug",
             print_face+Vector((0,-.019,.013)),(.042,.037,.058),steel,p,.003)
    for vertex in slug.data.vertices:
        vertex.co=undo_contact @ vertex.co
    for face,offset in [(lower,0),(upper,.026)]:
        mark=text(f"{ident} typeface {offset:.3f}",face,print_face+Vector((0,.0004,offset)),.027,dark,p,math.pi/2)
        mark.matrix_basis=Matrix.Translation(-world_origin(p)) @ undo_contact @ Matrix.Translation(world_origin(p)) @ mark.matrix_basis
    wire_x=(i-h_slot)*.058
    link=pivot(f"Hilda{ident}Link",(wire_x,-.09,.32),frame)
    links[i]=link
    input_pin=pivot(f"Hilda{ident}InputPin",(wire_x,-.23,.244),link)
    output_pin=pivot(f"Hilda{ident}OutputPin",(wire_x,-.205,.58),link)
    tail_pin=pivot(f"Hilda{ident}TailPin",root-radial*.046+Vector((0,0,-.018)),p)
    rod(tag+" rocking input arm",world_origin(input_pin),world_origin(link),.014,barsteel,link,8)
    rod(tag+" rocking output arm",world_origin(link),world_origin(output_pin),.014,barsteel,link,8)
    rod(tag+" typebar heel",root,world_origin(tail_pin),.014,barsteel,p,8)
    pin_wire(f"Hilda{ident}KeyWire",bpy.data.objects[f"Hilda{ident}KeyPin"],input_pin,.009)
    pin_wire(f"Hilda{ident}BarWire",output_pin,tail_pin,.009)
    rod(tag+" heel pin",root-tangent*.020,root+tangent*.020,.019,steel,p)

# Local +X follows each slot's tangent. Preserve the children's world rest
# transforms so a single local-axis stroke drives the whole fan in Godot.
bpy.context.view_layer.update()
for p,a in bar_axes:
    child_rest=[(child,child.matrix_basis.copy()) for child in p.children]
    p.rotation_euler.z=a
    for child,home in child_rest:
        child.matrix_basis=Matrix.Rotation(-a,4,'Z') @ home
brass=material("Olympia • tarnished linkage collars",(.40,.32,.17),.65,.38)
# Owner underside views 15–18 show the stepped lever bank and its cross shafts.
for x in (-1.38,1.38):
    box("Base frame rail",(x,-.02,.133),(.087,2.64,.098),dark,frame,.015)
for y,z in ((-.68,.118),(.57,.143),(.99,.18)):
    rod("Underside cross-shaft",(-1.39,y,z),(1.39,y,z),.029,steel,frame,20)
for i in range(len(printing_keys)):
    x=(i-h_slot)*.058
    dz=(i%3)*.009
    p=links[i]
    rod("Lower draw wire",(x,-.64,.127+dz),(x,.50,.158+dz),.009,steel,p,8)
    rod("Escapement-side bellcrank",(x,.50,.158+dz),(x,.77,.301+dz),.019,barsteel,p,8)
    rod("Bellcrank spacer",(x-.014,.57,.143),(x+.014,.57,.143),.050,brass,frame,14)
for i in range(13):
    x=(i-6)*.178
    rod("Rear fork arm",(x,.76,.18),(x,1.06,.29),.014,steel,frame,8)
for side in (-1,1):
    x=side*1.033
    for z,r,h,m in ((.76,.267,.036,dark),(.79,.192,.134,red),(.857,.195,.067,ribbonblack),(.924,.267,.027,dark)):
        rod("Ribbon reel",(x,.52,z),(x,.52,z+h),r,m,frame,48)
    rod("Reel retaining nut",(x,.52,.95),(x,.52,.974),.043,steel,frame,20)
    for z,m in ((.973,red),(1.025,ribbonblack)):
        pts=[(side*.96,.58),(side*.473,.77),(side*.237,.873),(0,.91)]
        mesh("Ribbon web",[(xx,yy,k) for xx,yy in pts for k in (z,z+.052)],
             [(i,i+2,i+3,i+1) for i in (0,2,4)],m,frame)
    rod("Ribbon fork",(side*.13,.88,.88),(side*.10,.91,1.09),.014,steel,frame)

# Carriage left end and return handpiece: compare owner photos 02, 12 and 19.
# Fixed shaft coordinates also register the runtime paper wrap to the platen.
axle_y, axle_z = 1.03, 1.12
roll=pivot("HildaPlatenRoll",(0,axle_y,axle_z),car)
ret=pivot("HildaReturnLever",(-1.515,1.304,1.167),car)
line_selector=pivot("HildaLineSpacingSelector",(-1.443,axle_y,axle_z),car)


def turned(name, profile, parent, materials, segments=128, corrugation=()):
    """Lathe an X-axis part. Rows specify X, radius, rib depth, and surface material."""
    verts=[]
    faces=[]
    for x,r,depth,mat_index in profile:
        for i in range(segments):
            a=math.tau*i/segments
            rr=r+depth*corrugation[i%len(corrugation)] if corrugation else r
            verts.append((x,axle_y+rr*math.cos(a),axle_z+rr*math.sin(a)))
    faces.append(tuple(reversed(range(segments))))
    for j in range(len(profile)-1):
        for i in range(segments):
            a=j*segments+i
            b=j*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    faces.append(tuple(range(len(verts)-segments,len(verts))))
    if profile[-1][0]<profile[0][0]:
        faces=[face[::-1] for face in faces]
    ob=mesh(name,verts,faces,materials[0],parent)
    for mat in materials[1:]:
        ob.data.materials.append(mat)
    for poly in ob.data.polygons:
        if 0<poly.index<len(faces)-1:
            ring=(poly.index-1)//segments
            poly.material_index=profile[ring][3]
            poly.use_smooth=True
    ob.data.polygons[-1].material_index=profile[-1][3]
    return ob


rod("Platen axle",(-1.73,axle_y,axle_z),(1.73,axle_y,axle_z),.045,steel,roll,24)
# Photo 12 shows faint, pitch-spaced polished strike tracks on the bare rubber.
wear=material("Olympia polished platen tracks",(.051,.047,.043),.03,.58)
rubber_profile=[(-1.39,.114,0,0),(-1.377,.12,0,0)]
for i in range(75):
    x=(i-37)*.0318
    rubber_profile.extend([(x,.12,0,1),(x+.0022,.1201,0,0)])
rubber_profile.extend([(1.377,.12,0,0),(1.39,.114,0,0)])
turned("Rubber platen",rubber_profile,roll,[rubber,wear],64)
box("Paper table",(0,1.27,1.13),(2.77,.057,.317),base,car,.018)
box("Graduated carriage rail",(0,1.37,1.30),(2.87,.079,.088),ivory,car,.014)
for i in range(81):
    x=(i-40)*.034
    h=.035 if i%5==0 else .019
    box("Pitch index",(x,1.329,1.342-h/2),(.0035,.003,h),dark,car,0)
    if i%10==0:
        text("Carriage scale "+str(i),str(i),(x,1.327,1.284),.032,black,car,math.pi/2)
rod("Paper bail",(-1.38,.982,1.27),(1.38,.982,1.27),.014,steel,car)
for s,side in ((-1,"Left"),(1,"Right")):
    x=s*1.48
    # Rear folded carriage cheek tapers to a downward ear around the spindle.
    cheek=[(.811,1.249),(1.015,1.276),(1.307,1.235),(1.333,1.194),
           (1.317,.991),(1.19,.987),(1.103,.943),(.985,.947),(.825,1.040)]
    xs=sorted((s*1.48,s*1.535))
    end=skin(side+" carriage bearing cheek",[[(xx,y,z) for y,z in cheek[::-1]] for xx in xs],steel,car,.012)
    cut(end,rod("Bearing cutter",(xs[0]-.04,axle_y,axle_z),(xs[1]+.04,axle_y,axle_z),.079,dark,car,32))
    rod(side+" spindle bush",(s*1.48,axle_y,axle_z),(s*1.548,axle_y,axle_z),.067,barsteel,car,32)
    # Narrow ivory spindle collar, fluted cream drum, radiused green end insert.
    # All faces of each knob share one mesh so the complete left knob can pull out.
    knob_profile=[(1.52,.054,0,0),(1.614,.055,0,0),(1.622,.127,0,0),
                  (1.628,.139,.001,0),(1.638,.145,.0021,0),(1.769,.145,.0021,0),
                  (1.778,.142,.001,0),(1.781,.139,0,1),(1.784,.135,0,1),
                  (1.789,.124,0,1),(1.792,.096,0,1)]
    turned("HildaPlatenKnob"+side,[(s*x,r,d,m) for x,r,d,m in knob_profile],roll,
           [ivory,sage],240,(0,1,1,0))
    rod("Bail roller",(s*.55,.982,1.27),(s*.71,.982,1.27),.05,rubber,car,24)
    rod("Bail hinge arm",(s*1.39,.982,1.27),(s*1.39,1.19,1.115),.015,steel,car)
    box("Margin stop",(s*.99,1.36,1.355),(.075,.105,.044),barsteel,car)
    mesh(side+" margin pointer",[(s*.99,1.306,1.371),(s*.99-.014,1.306,1.351),
                                (s*.99+.014,1.306,1.351)],[(0,1,2)],red,car)
# A toothed wheel shows between the platen and the polished selector sector in 19.
# 36 teeth approximate a half-line detent given the measured roller/pitch ratio.
turned("HildaPlatenRatchet",[(-1.422,.135,.009,0),(-1.391,.135,.009,0)],roll,
       [dark],144,(0,.92,1,0))
rod("Return hinge socket",(-1.515,1.304,1.091),(-1.515,1.304,1.17),.073,steel,car,32)
rod("Return shoulder pin",(-1.515,1.304,1.167),(-1.515,1.304,1.204),.038,barsteel,ret,24)
# One bent sheet runs continuously over the knob, then widens into a long paddle.
# Section positions follow the top-view sweep and the nearly horizontal upper edge
# seen in profile, with a rolled lip on each side of the handpiece.
sections=[(-1.513,1.322,1.190,.085,.022),(-1.515,1.249,1.191,.091,.022),
          (-1.536,1.215,1.209,.086,.027),(-1.567,1.155,1.351,.074,.032),
          (-1.586,1.117,1.407,.077,.027),(-1.60,1.087,1.423,.083,.023),
          (-1.659,.778,1.424,.085,.024),(-1.694,.59,1.424,.100,.032),
          (-1.704,.552,1.424,.116,.108),(-1.711,.519,1.424,.116,.122),
          (-1.873,-.453,1.423,.101,.137),(-1.875,-.48,1.420,.094,.125)]
def paddle_ring(x,y,z,w,h):
    return [(x-w*.5,y,z-h+.008),(x-w*.46,y,z-h),(x+w*.46,y,z-h),
            (x+w*.5,y,z-h+.008),(x+w*.5,y,z-.005),(x+w*.45,y,z),
            (x-w*.45,y,z),(x-w*.5,y,z-.005)]
skin("Return formed chrome arm",[paddle_ring(*s) for s in sections],steel,ret,.004)
grip_sections=[(-1.71,.527,1.404,.102,.078),(-1.715,.499,1.404,.122,.091),
               (-1.871,-.438,1.402,.107,.102),(-1.874,-.462,1.398,.096,.093)]
skin("HildaReturnGrip",[paddle_ring(*s) for s in grip_sections],dark,ret,.006)
# Owner photo 19: three burgundy capsule-shaped enamel indexes behind a screw;
# the curled metal selector tab glides above this fixed sector.
wine=material("Olympia engraved index enamel",(.103,.024,.023),0,.47)
def sector_point(x,angle,r):
    return (x,axle_y+r*math.sin(angle),axle_z+r*math.cos(angle))
arc=[math.radians(k) for k in range(-59,46,4)]
profile=[sector_point(-1.48,a,.173) for a in arc]+[sector_point(-1.48,a,.163) for a in reversed(arc)]
skin("Polished line spacing index sector",[[(x,y,z) for _,y,z in reversed(profile)] for x in (-1.485,-1.425)],steel,car,.004)
for idx,a in enumerate((-.19,-.018,.154)):
    pts=[]
    for k in range(16):
        t=k*math.tau/16
        pts.append(sector_point(-1.453+.021*math.cos(t),a+.036*math.sin(t),.174))
    mesh("Line spacing index "+str(idx+1),pts,[tuple(range(len(pts)))],wine,car)
# Flat-head screw normal to the sloping face of the sector.
a=-.585
screw_top=Vector(sector_point(-1.455,a,.175))
normal=Vector((0,math.sin(a),math.cos(a)))
rod("Selector sector retaining screw",screw_top-normal*.009,screw_top,.019,barsteel,car,24)
tangent=Vector((0,math.cos(a),-math.sin(a)))
long_axis=Vector((.014,0,0))+tangent*.004
short_axis=tangent*.002-Vector((.0006,0,0))
mesh("Index screw slot",[screw_top+normal*.001+u*long_axis+v*short_axis
                        for u,v in ((-1,-1),(1,-1),(1,1),(-1,1))],[(0,1,2,3)],black,car)
tongue=[(-1.457,1.038,1.178,.039,.083),(-1.461,1.082,1.274,.042,.036),
        (-1.458,1.087,1.304,.051,.021),(-1.467,1.066,1.323,.055,.016),
        (-1.471,1.043,1.323,.053,.016)]
skin("HildaLineSpacingHandle",[paddle_ring(*s) for s in tongue],steel,line_selector,.004)
guide=material("Olympia • amber transparent line guides",(.76,.60,.35),0,.19)
guide.diffuse_color=(.76,.60,.35,.27)
guide.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value=.27
for side in (-1,1):
    box("Clear acrylic line guide",(side*.51,.889,1.129),(.67,.012,.125),guide,frame,.014)

# Centre mesh origins for direct manipulation and meaningful Blender selection.
for obj in scene.objects:
    if obj.type!='MESH' or not obj.data.vertices or obj.constraints:
        continue
    local_center=sum((Vector(b) for b in obj.bound_box),Vector())/8
    if local_center.length_squared<1e-12:
        continue
    for v in obj.data.vertices:
        v.co-=local_center
    obj.location+=obj.rotation_euler.to_matrix()@local_center

scene.world=bpy.data.worlds.new("Hilda studio world")
scene.world.color=(.23,.23,.23)
camera_data=bpy.data.cameras.new("Owner view")
camera=bpy.data.objects.new("Owner view",camera_data)
scene.collection.objects.link(camera)
camera.location=(1.45,-7.1,4.65)
camera.rotation_euler=(Vector((0,0,1.78))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=5.25
scene.camera=camera
for a in bpy.context.screen.areas:
    if a.type=='VIEW_3D':
        space=a.spaces.active
        space.region_3d.view_perspective='CAMERA'
        space.shading.color_type='MATERIAL'
scene.render.engine='BLENDER_WORKBENCH'
shading=scene.display.shading
shading.color_type='MATERIAL'
shading.light='STUDIO'
shading.show_shadows=True
shading.show_cavity=True
shading.cavity_type='WORLD'
scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage=930,900,100
scene.render.film_transparent=False
scene.render.filepath=str(Path(tempfile.gettempdir())/'hilda-model'/'Hilda preview.png')
Path(scene.render.filepath).parent.mkdir(exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "Hilda - Olympia SM9 De Luxe.blend"))
bpy.ops.export_scene.gltf(filepath=str(APP/"Hilda.glb"),export_format='GLB',export_apply=True,
                          export_cameras=False,export_lights=False,export_animations=False)
bpy.ops.render.render(write_still=True)
