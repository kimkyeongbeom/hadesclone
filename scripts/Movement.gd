class_name Movement
extends RefCounted

## 플레이어와 적이 함께 쓰는 이동 도우미.


## move_and_slide() 직후에 부른다. 나무에 정면으로 부딪혀 미끄러질 방향이 없으면
## 나무 옆으로 살짝 틀어 한 번 더 움직인다.
static func slide_around_trees(body: CharacterBody3D, direction: Vector3, speed: float, stuck_ratio: float) -> void:
	if body.get_real_velocity().length() >= speed * stuck_ratio:
		return
	for i in body.get_slide_collision_count():
		var collision := body.get_slide_collision(i)
		var collider := collision.get_collider()
		if not (collider is Node and collider.is_in_group("trees")):
			continue
		var tangent := collision.get_normal().cross(Vector3.UP)
		tangent.y = 0.0
		if tangent.dot(direction) < 0.0:
			tangent = -tangent
		body.velocity = tangent.normalized() * speed
		body.move_and_slide()
		return


## 바닥 위에서 방향만 남긴다 (y = 0, 길이 1). 길이가 0이면 fallback을 쓴다.
static func flat_direction(from: Vector3, to: Vector3, fallback := Vector3.FORWARD) -> Vector3:
	var direction := to - from
	direction.y = 0.0
	if direction.length() < 0.001:
		return fallback
	return direction.normalized()
