extends RefCounted
## Physical slug identifiers match the Blender action bank and the optical manifest.
const SHORTCUTS := {KEY_Q:"¼", KEY_H:"½", KEY_T:"¾", KEY_P:"¢"}
const ALIASES := {"1":["L",0]}
## Owner's keyboard photo 09, in physical left-to-right row order.
const ROWS := ["=234567890-¾","QWERTYUIOP½","ASDFGHJKL;¢","ZXCVBNM,./"]
const SHIFTED_SYMBOL := {
	"=":"+", "2":'"', "3":"#", "4":"$", "5":"%", "6":"_", "7":"&", "8":"'",
	"9":"(", "0":")", "-":"*", "¾":"!", "½":"¼", ";":":", "¢":"@", ",":",", ".":".", "/":"?"
}
const POSITIONS := {
	KEY_1:"=", KEY_2:"2", KEY_3:"3", KEY_4:"4", KEY_5:"5", KEY_6:"6", KEY_7:"7",
	KEY_8:"8", KEY_9:"9", KEY_0:"0", KEY_MINUS:"-", KEY_EQUAL:"¾",
	KEY_BRACKETLEFT:"½", KEY_SEMICOLON:";", KEY_APOSTROPHE:"¢", KEY_COMMA:",",
	KEY_PERIOD:".", KEY_SLASH:"/"
}
const DEAD_FACES := []
const COMPOSE := {}
# The Hilda desk supports momentary Shift. Lock release awaits observation.
const SHIFT_RELEASE_LOCATION := -1
const SHIFT_RELEASE_KEY := ""

static func physical_pair(key:int) -> String:
	if key >= KEY_A and key <= KEY_Z: return String.chr(key)
	return POSITIONS.get(key,"")

static func faces_for(label:String) -> Array:
	if SHIFTED_SYMBOL.has(label): return [label,SHIFTED_SYMBOL[label]]
	if label.length() == 1 and label.unicode_at(0) >= KEY_A and label.unicode_at(0) <= KEY_Z:
		return [label.to_lower(),label]
	return []
