extends Resource
## Physical identity and runtime assets for one playable typewriter.
## Assign a profile to the writing desk scene. Both raster sources belong to
## the same typing specimen; they must share the manifest's character cells.
@export var id:String
@export var nickname:String
@export var model:String
@export var rig_script:Script
@export_file("*.json") var manifest_path:String
@export_file var geometry_path:String
@export var strike_atlas:Texture2D
@export var pressure_atlas:Texture2D
@export_dir var sound_directory:String
@export var autosave_path:String
@export var document_extension:String
@export var keyboard:Script
@export var ribbon_modes:Array[String]
@export_multiline var credits:String
@export_multiline var operator_notes:String

func load_manifest()->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
