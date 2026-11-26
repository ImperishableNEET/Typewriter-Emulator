extends RefCounted
## Keep the two draw wires seated between independently moving pivots.
## The head radius is fixed; longitudinal motion approximates pin clearance
## and compliance where Hilda's hidden linkage dimensions are unknown.
var wires: Dictionary = {}

func setup(model: Node3D, actions: Dictionary) -> void:
	var parts := {}
	for node in model.find_children("Hilda*", "Node3D", true, false):
		parts[node.name] = node
	for label in actions:
		var prefix := str(actions[label][0]).trim_suffix("Key")
		var pairs: Array = []
		for suffix in [["KeyWire","KeyPin","InputPin"], ["BarWire","OutputPin","TailPin"]]:
			var rod: Node3D = parts.get(prefix + suffix[0])
			var start: Node3D = parts.get(prefix + suffix[1])
			var end: Node3D = parts.get(prefix + suffix[2])
			if rod and start and end:
				pairs.append([rod, start, end])
		if not pairs.is_empty():
			wires[label] = pairs
			pose(label)

func pose(label: String) -> void:
	for assembly in wires.get(label, []):
		var wire: Node3D = assembly[0]
		var start: Vector3 = assembly[1].global_position
		var span: Vector3 = assembly[2].global_position - start
		var direction := span.normalized()
		if direction.is_zero_approx(): continue
		var up := Vector3.RIGHT if absf(direction.y) > 0.97 else Vector3.UP
		var basis := Basis.looking_at(direction, up)
		basis.z *= span.length()
		wire.global_transform = Transform3D(basis, start)

func sync_basket() -> void:
	# A Shift stroke moves the tail pin on every bar, even between strikes.
	for label in wires:
		pose(label)
