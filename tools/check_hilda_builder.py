"""Check photographed legends in the Blender source before importing the baked model."""
import ast
from pathlib import Path


root = Path(__file__).resolve().parents[1]
path = root / "Source/hilda/build_hilda.py"
source = path.read_text(encoding="utf-8")
tree = ast.parse(source, filename=str(path))
rows = next(node.value for node in tree.body if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == "rows" for target in node.targets))
legends = {
    tuple(item.value for item in node.elts)
    for node in ast.walk(rows) if isinstance(node, ast.Tuple)
    and all(isinstance(item, ast.Constant) for item in node.elts)
}
expected = {("!", "\u00be"), ("\u00bc", "\u00bd"), ("@", "\u00a2"), ("\u2192",)}
if missing := expected - legends:
    raise SystemExit(f"Hilda keyboard legends missing from the Blender source: {sorted(missing)}")
for prefix in ("\u00c2", "\u00e2\u20ac", "\u00e2\u2020", "\ufffd"):
    if prefix in source:
        raise SystemExit(f"Possible UTF-8 decoding damage in {path.name}: {prefix!a}")
print("HILDA_BUILDER_LEGENDS_OK")
