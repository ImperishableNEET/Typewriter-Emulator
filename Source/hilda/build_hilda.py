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


enamel = material("Olympia â€¢ warm ivory enamel", (.70,.64,.49), .16,.31)
base = material("Olympia â€¢ textured basalt chassis", (.17,.16,.14), .32,.54)
ivory = material("Olympia â€¢ cream keytop", (.82,.775,.638), .02,.32)
sage = material("Olympia â€¢ sea green controls", (.34,.49,.375), .05,.31)
steel = material("Olympia â€¢ bright steel", (.61,.62,.60), .82,.25)
barsteel = material("Olympia â€¢ typebar steel", (.38,.375,.34), .70,.32)
dark = material("Olympia â€¢ phosphated iron", (.053,.054,.051), .65,.39)
rubber = material("Olympia â€¢ platen rubber", (.032,.030,.028), .03,.74)
black = material("Olympia â€¢ black legends", (.013,.013,.012), .03,.44)
red = material("Olympia â€¢ red silk", (.32,.022,.029), .0,.82)
ribbonblack = material("Olympia â€¢ black silk", (.028,.019,.025), .0,.82)
teal = material("Olympia â€¢ segment medallion", (.112,.18,.18), .24,.46)
blue = material("Olympia â€¢ selector blue", (.017,.044,.14))


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
    for label,x0,x1,profile,mat in [
        ("lower casting",1.51,1.66,[(-1.58,.14),(-1.58,.25),(-.9,.38),(-.30,.54),
             (.70,.68),(1.08,.58),(1.43,.69),(1.47,.53),(1.32,.13)],base),
        ("removable cover cheek",1.50,1.655,[(-1.58,.25),(-1.58,.32),(-1.18,.43),
             (-.76,.56),(-.53,.68),(-.38,.86),(-.32,1.035),(-.22,1.08),
             (.71,1.085),(.74,.68),(-.30,.54),(-.90,.38)],enamel)]:
        # Side profiles are clockwise when viewed from the machine's right.
        p=frame if mat==base else cover
        rings=[[(x,y,z) for y,z in reversed(profile)] for x in sorted((side*x0,side*x1))]
        skin(name+" "+label,rings,mat,p,.033)
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
support=pivot("HildaPaperSupport",(0,1.35,1.2),car)
box("Stowed telescopic paper support",(.691,1.355,1.21),(1.41,.083,.028),steel,support,.008)
box("Front fascia",(0,-1.525,.225),(3.28,.12,.13),base,frame,.040)
box("Front rolled ivory sill",(0,-1.51,.302),(3.27,.15,.085),enamel,cover,.035)
# The cover has an open-backed, reentrant trapezoid. No flat surface covers the basket.
outline=[(-1.65,-.36),(1.65,-.36),(1.64,.75),(.40,.75),(.38,.68),
         (.93,-.08),(.92,-.14),(-.92,-.14),(-.93,-.08),(-.38,.68),(-.40,.75),(-1.64,.75)]
skin("Rolled ivory hood with basket aperture",
     [[(x,y,z+.035*y) for x,y in outline] for z in (1.016,1.085)],enamel,cover,.030)
box("Olympia emblem fascia",(0,-.315,.925),(3.18,.093,.296),enamel,cover,.035)
script_path=Path("C:/Windows/Fonts/BRUSHSCI.TTF")
script=bpy.data.fonts.load(str(script_path)) if script_path.exists() else None
text("Raised Olympia script","Olympia",(0,-.364,.94),.182,steel,cover,math.pi/2,script)

# Owner photo 09 shows an exclamation mark above the three-quarters fraction.
rows=[
    [("+","="),('"',"2"),("#","3"),("$","4"),("%","5"),("_","6"),("&","7"),
     ("'","8"),("(","9"),(")","0"),("*","-"),("!","Â¾"),("TAB",)],
    [("M R",)]+[(v,) for v in "QWERTYUIOP"]+[("Â¼","Â½"),("â†’",)],
    [("",)]+[(v,) for v in "ASDFGHJKL"]+[(":",";"),("@","Â¢")],
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
            ident=part_names.get(lower,upper)
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
    box("Ribbon selector index "+str(i),(1.582,-.96-i*.075,.505-i*.024),(.041,.032,.012),m,cover,.004)

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
brass=material("Olympia â€¢ tarnished linkage collars",(.40,.32,.17),.65,.38)
# Owner underside views 15â€“18 show the stepped lever bank and its cross shafts.
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

# Platen, paper table, bail, stops and left carriage-return lever from 02/12/13.
rod("Platen axle",(-1.73,1.03,1.12),(1.73,1.03,1.12),.045,steel,car,20)
rod("Rubber platen",(-1.39,1.03,1.12),(1.39,1.03,1.12),.12,rubber,car,64)
box("Paper table",(0,1.27,1.13),(2.77,.057,.317),base,car,.018)
box("Graduated carriage rail",(0,1.37,1.30),(2.87,.079,.088),ivory,car,.014)
for i in range(79):
    x=(i-39)*.034
    h=.032 if i%5==0 else .016
    box("Pitch index",(x,1.327,1.30+h/2),(.004,.004,h),dark,car,0)
rod("Paper bail",(-1.38,.982,1.27),(1.38,.982,1.27),.014,steel,car)
for s in (-1,1):
    x=s*1.48
    box("Carriage end casting",(x,1.095,1.065),(.135,.496,.287),barsteel,car,.032)
    rod("Platen knob",(s*1.58,1.03,1.12),(s*1.745,1.03,1.12),.147,ivory,car,52)
    rod("Green platen knob insert",(s*1.743,1.03,1.12),(s*1.753,1.03,1.12),.134,sage,car,52)
    for j in range(48):
        a=j*math.tau/48
        y,z=1.03+.146*math.cos(a),1.12+.146*math.sin(a)
        rod("Knob knurl",(s*1.59,y,z),(s*1.739,y,z),.0035,ivory,car,5)
    rod("Bail roller",(s*.55,.982,1.27),(s*.71,.982,1.27),.05,rubber,car,24)
    rod("Bail hinge arm",(s*1.39,.982,1.27),(s*1.39,1.19,1.115),.015,steel,car)
    box("Margin stop",(s*.99,1.36,1.355),(.075,.105,.044),barsteel,car)
rod("Return lever neck",(-1.48,1.21,1.19),(-1.60,1.06,1.40),.027,steel,car)
rod("Return lever arm",(-1.60,1.06,1.40),(-1.69,.14,1.40),.032,steel,car)
box("Return lever black grip",(-1.69,.055,1.397),(.106,.48,.055),dark,car,.021)
skin("Return lever polished spine",[
    [(-1.74,-.43,z),(-1.718,-.47,z),(-1.57,.99,z),(-1.62,1.04,z)]
    for z in (1.421,1.438)],steel,car,.008)
guide=material("Olympia â€¢ amber transparent line guides",(.76,.60,.35),0,.19)
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
camera.location=(2.10,-5.55,3.95)
camera.rotation_euler=(Vector((0,0,.71))-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.type='ORTHO'
camera.data.ortho_scale=4.60
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
scene.render.resolution_x,scene.render.resolution_y,scene.render.resolution_percentage=900,670,100
scene.render.film_transparent=False
scene.render.filepath=str(Path(tempfile.gettempdir())/'hilda-model'/'Hilda preview.png')
Path(scene.render.filepath).parent.mkdir(exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / "Hilda - Olympia SM9 De Luxe.blend"))
bpy.ops.export_scene.gltf(filepath=str(APP/"Hilda.glb"),export_format='GLB',export_apply=True,
                          export_cameras=False,export_lights=False,export_animations=False)
bpy.ops.render.render(write_still=True)
