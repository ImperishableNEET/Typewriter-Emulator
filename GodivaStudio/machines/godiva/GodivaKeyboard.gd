extends RefCounted
## Physical key identifiers match bar names in Godiva's exported linkage.
const SHORTCUTS={KEY_C:"ç",KEY_E:"é",KEY_Q:"¼",KEY_H:"½",KEY_P:"¢"}
const ALIASES={"1":["L",0]}
const DEAD_FACES=["`","^"]
const COMPOSE={"à":"`a","è":"`e","ì":"`i","ò":"`o","ù":"`u","â":"^a","ê":"^e","î":"^i","ô":"^o","û":"^u","À":"`A","È":"`E","Ù":"`U","Â":"^A","Ê":"^E","Î":"^I","Ô":"^O","Û":"^U"}
const SHIFT_RELEASE_LOCATION=KEY_LOCATION_LEFT
const SHIFT_RELEASE_KEY="Left shift"
const POSITIONS={
	KEY_2:'" / 2',KEY_3:"# / 3",KEY_4:"$ / 4",KEY_5:"% / 5",KEY_6:"_ / 6",
	KEY_7:"& / 7",KEY_8:"' / 8",KEY_9:"( / 9",KEY_0:") / 0",
	KEY_MINUS:"/ / -",KEY_EQUAL:"! / =",KEY_BRACKETLEFT:"¼ / ½",KEY_BRACKETRIGHT:"@ / ¢",
	KEY_SEMICOLON:": / ;",KEY_APOSTROPHE:"^ / `",KEY_COMMA:"? / ,",KEY_PERIOD:". / .",KEY_SLASH:"ç / é"
}

static func physical_pair(key:int)->String:
	if key>=KEY_A and key<=KEY_Z:return char(key)
	return POSITIONS.get(key,"")

static func faces_for(label:String)->Array:
	if label.length()==1:return [label.to_lower(),label]
	var faces=label.split(" / ",true,1)
	return [faces[1],faces[0]]
