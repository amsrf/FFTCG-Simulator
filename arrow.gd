extends Node3D

func point_y_axis_to(target: Vector3):
	var direction = (target - global_transform.origin).normalized()

	# Step 1: Extract scale from original basis
	var scale = Vector3(
		global_transform.basis.x.length(),
		global_transform.basis.y.length(),
		global_transform.basis.z.length()
	)

	# Step 2: Build a new orthonormal basis with +Y pointing to direction
	var up = direction
	var forward = Vector3.FORWARD
	if abs(up.dot(forward)) > 0.99:
		forward = Vector3.RIGHT

	var right = up.cross(forward).normalized()
	forward = right.cross(up).normalized()

	var new_basis = Basis()
	new_basis.x = right * scale.x
	new_basis.y = up * scale.y
	new_basis.z = forward * scale.z

	# Step 3: Assign new basis while preserving origin
	global_transform = Transform3D(new_basis, global_transform.origin)
