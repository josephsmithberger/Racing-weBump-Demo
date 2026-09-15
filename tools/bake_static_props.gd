@tool
extends EditorScript
## Bakes the static decoration props in main.tscn (the parked trucks) into one
## ArrayMesh with one surface per distinct material, so they cost one draw call
## in the color pass and one in the shadow pass instead of 18 each.
##
## The GridMap is deliberately left alone: baking its 154 cells multiplies the
## shared tile geometry into a ~5 MB mesh and loses per-octant culling and LODs.
##
## Re-run from the editor (File > Run, or `xo eval --file tools/bake_static_props.gd`)
## after moving or adding props whose names start with PROP_NAME_PREFIX, and
## keep those source nodes hidden in the scene.

const SCENE_PATH := "res://scenes/main.tscn"
const OUTPUT_PATH := "res://models/static_props_baked.res"
const PROP_NAME_PREFIX := "vehicle-truck-"
const INCLUDE_GRIDMAP := false

func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	var root: Node3D = packed.instantiate()
	var tools: Dictionary = {}  # material resource -> SurfaceTool
	var stats := {"cells": 0, "props": 0, "surfaces": 0}

	var grid: GridMap = root.get_node("GridMap")
	var grid_xform := _xform_to_root(grid)
	for cell in (grid.get_used_cells() if INCLUDE_GRIDMAP else []):
		var item := grid.get_cell_item(cell)
		if item < 0:
			continue
		var mesh := grid.mesh_library.get_item_mesh(item)
		if mesh == null:
			continue
		var cell_xform := Transform3D(grid.get_basis_with_orthogonal_index(grid.get_cell_item_orientation(cell)), grid.map_to_local(cell))
		var xform := grid_xform * cell_xform * grid.mesh_library.get_item_mesh_transform(item)
		_append_mesh(tools, mesh, xform, null, stats)
		stats.cells += 1

	for child in root.get_children():
		if not child.name.begins_with(PROP_NAME_PREFIX):
			continue
		for mi in child.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			_append_mesh(tools, mi.mesh, _xform_to_root(mi), mi, stats)
			stats.props += 1

	var baked := ArrayMesh.new()
	baked.resource_name = "track_baked"
	for key in tools:
		var st: SurfaceTool = tools[key]
		st.index()
		st.commit(baked)
		baked.surface_set_material(baked.get_surface_count() - 1, st.get_meta("material"))
		stats.surfaces += 1
	root.free()

	var err := ResourceSaver.save(baked, OUTPUT_PATH, ResourceSaver.FLAG_COMPRESS)
	print("[bake_static_props] %s -> %s (cells %d, prop meshes %d, surfaces %d)" % [error_string(err), OUTPUT_PATH, stats.cells, stats.props, stats.surfaces])

func _append_mesh(tools: Dictionary, mesh: Mesh, xform: Transform3D, mi: MeshInstance3D, _stats: Dictionary) -> void:
	for s in range(mesh.get_surface_count()):
		var material: Material = null
		if mi != null:
			material = mi.material_override
			if material == null:
				material = mi.get_surface_override_material(s)
		if material == null:
			material = mesh.surface_get_material(s)
		# Materials live inside other resources (mesh library, imported glb);
		# embed a copy so the baked mesh stands alone. Key by content so the
		# per-file material copies that glb import creates merge into one surface.
		var key := _material_key(material)
		if not tools.has(key):
			var new_tool := SurfaceTool.new()
			new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			new_tool.set_meta("material", material.duplicate() if material else null)
			tools[key] = new_tool
		var st: SurfaceTool = tools[key]
		st.append_from(mesh, s, xform)

func _material_key(material: Material) -> String:
	if material == null:
		return "none"
	if material is BaseMaterial3D:
		var m := material as BaseMaterial3D
		var tex := m.albedo_texture.resource_path if m.albedo_texture else ""
		return "%s|%s|%d|%d|%d|%d" % [tex, m.albedo_color, m.cull_mode, m.texture_filter, m.shading_mode, m.transparency]
	return material.resource_path + "::" + str(material.get_instance_id())

func _xform_to_root(node: Node3D) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n.get_parent() != null:
		if n is Node3D:
			xform = (n as Node3D).transform * xform
		n = n.get_parent()
	return xform
