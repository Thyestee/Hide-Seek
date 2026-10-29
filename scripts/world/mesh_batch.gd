extends RefCounted
## Collects coloured primitives into a single mesh, so a prop (or a whole
## house) costs one draw call instead of dozens of separate meshes.

static var _solid_material: StandardMaterial3D
static var _glow_material: StandardMaterial3D

var _solid := _Bucket.new()
var _glow := _Bucket.new()


class _Bucket:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()


func is_empty() -> bool:
	return _solid.verts.is_empty() and _glow.verts.is_empty()


func add(mesh: PrimitiveMesh, xform: Transform3D, color: Color, glow := false) -> void:
	var bucket := _glow if glow else _solid
	var arrays := mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var base := bucket.verts.size()
	var normal_basis := xform.basis.inverse().transposed()
	for i in verts.size():
		bucket.verts.append(xform * verts[i])
		bucket.normals.append((normal_basis * normals[i]).normalized())
		bucket.colors.append(color)
	if indices.is_empty():
		for i in verts.size():
			bucket.indices.append(base + i)
	for index in indices:
		bucket.indices.append(base + index)


func build() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for pair in [[_solid, solid_material()], [_glow, glow_material()]]:
		var bucket: _Bucket = pair[0]
		if bucket.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bucket.verts
		arrays[Mesh.ARRAY_NORMAL] = bucket.normals
		arrays[Mesh.ARRAY_COLOR] = bucket.colors
		arrays[Mesh.ARRAY_INDEX] = bucket.indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
	return mesh


func build_instance(node_name := "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = build()
	return mi


static func solid_material() -> StandardMaterial3D:
	if _solid_material == null:
		_solid_material = StandardMaterial3D.new()
		_solid_material.vertex_color_use_as_albedo = true
		_solid_material.vertex_color_is_srgb = true
		_solid_material.roughness = 0.85
	return _solid_material


static func glow_material() -> StandardMaterial3D:
	if _glow_material == null:
		_glow_material = StandardMaterial3D.new()
		_glow_material.vertex_color_use_as_albedo = true
		_glow_material.vertex_color_is_srgb = true
		_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow_material
