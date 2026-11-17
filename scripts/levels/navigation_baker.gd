class_name NavigationBaker
extends RefCounted
## Bakes a NavigationRegion3D from gray-box CSGBox3D geometry.
##
## Builds the source geometry from the boxes' sizes and transforms on the CPU,
## instead of letting the engine parse CSG meshes: that path reads meshes back
## from the GPU and finds nothing in headless runs (CI, tests).


## Bakes [param region]'s navigation mesh from every colliding CSGBox3D under
## it. Returns the number of polygons.
static func bake_csg_boxes(region: NavigationRegion3D) -> int:
	# Bake into a copy: assigning the region's own resource back wouldn't push
	# the new polygons to the navigation server.
	var navigation_mesh: NavigationMesh = (
		region.navigation_mesh.duplicate() if region.navigation_mesh else NavigationMesh.new()
	)
	var source := NavigationMeshSourceGeometryData3D.new()
	_add_boxes(region, source, navigation_mesh.geometry_collision_mask)
	NavigationServer3D.bake_from_source_geometry_data(navigation_mesh, source)
	region.navigation_mesh = navigation_mesh
	return navigation_mesh.get_polygon_count()


static func _add_boxes(node: Node, source: NavigationMeshSourceGeometryData3D, mask: int) -> void:
	for child in node.get_children():
		var box := child as CSGBox3D
		if box != null and box.use_collision and box.collision_layer & mask != 0:
			var mesh := BoxMesh.new()
			mesh.size = box.size
			source.add_mesh_array(mesh.get_mesh_arrays(), box.global_transform)
		_add_boxes(child, source, mask)


## The navigation map syncs asynchronously: waits (up to [param max_frames]
## physics frames) until [param region] owns the map around [param probe], so
## NPCs get paths from their first tick. Returns false on timeout.
static func wait_for_region(region: NavigationRegion3D, probe: Vector3, max_frames: int) -> bool:
	var tree := region.get_tree()
	var map := region.get_navigation_map()
	for i in max_frames:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) == 0:
			continue
		if NavigationServer3D.map_get_closest_point_owner(map, probe) == region.get_rid():
			return true
	push_warning("NavigationBaker: navigation map not ready; NPCs steer directly until it is.")
	return false
