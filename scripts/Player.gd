class_name Player
extends CharacterBody3D

signal died
signal health_changed(current: float, maximum: float)
## 스킬을 쓰면 칸 번호(0 근접, 1 미사일, 2 순간이동)와 쿨다운을 알린다.
signal skill_used(slot: int, cooldown: float)

enum Skill { MELEE, MISSILE, TELEPORT }

## 이동 속도 (m/s)
@export var move_speed := 5.0
## 목표 지점까지 이 거리 안으로 들어오면 멈춤 (m)
@export var stop_distance := 0.2
## 몸을 이동 방향으로 돌리는 빠르기
@export var turn_speed := 15.0
## 클릭 목표를 이 범위(±m) 안으로 잘라 벽 앞에서 멈추게 함
@export var map_half_size := 19.5
## 나무에 정면으로 막혔다고 보는 기준 (실제 속도 / 원래 속도)
@export var stuck_ratio := 0.5
## 클릭 표시 원이 보이는 시간 (초)
@export var click_marker_time := 0.3

## 최대 체력
@export var max_health := 100.0
## 피격 후 무적 시간 (초)
@export var hurt_invincible_time := 0.5
## 피격 무적 중 깜빡이는 간격 (초)
@export var blink_interval := 0.05

## 근접 공격 피해
@export var melee_damage := 20.0
## 근접 공격 사거리 (m)
@export var melee_range := 1.8
## 근접 공격 부채꼴 각도 (도)
@export var melee_angle := 90.0
## 근접 공격 넉백 거리 (m)
@export var melee_knockback := 1.0
## 근접 공격 쿨다운 (초)
@export var melee_cooldown := 0.4
## 부채꼴 이펙트가 보이는 시간 (초)
@export var melee_effect_time := 0.1
## 공격 후 제자리에 서 있는 시간 (초)
@export var attack_stand_time := 0.15

## 매직 미사일 씬
@export var missile_scene: PackedScene
## 미사일을 넣을 노드 (Main의 Projectiles). 비어 있으면 플레이어의 부모.
@export var projectile_parent: Node3D
## 매직 미사일 쿨다운 (초)
@export var missile_cooldown := 0.6
## 미사일이 나오는 위치: 몸 중심에서 앞으로 (m)
@export var missile_spawn_forward := 0.5
## 미사일이 나오는 높이 (m)
@export var missile_spawn_height := 1.0

## 순간이동 최대 거리 (m)
@export var teleport_distance := 4.0
## 순간이동 도착 직후 무적 시간 (초)
@export var teleport_invincible_time := 0.3
## 순간이동 쿨다운 (초)
@export var teleport_cooldown := 3.0
## 출발점·도착점 파란 원이 보이는 시간 (초)
@export var teleport_effect_time := 0.3

## 움직일 때 반복하는 애니메이션
@export var run_animation := &"run"
## 검이 없을 때 공격 애니메이션 (근접 공격·미사일)
@export var punch_animation := &"punch"
## 검을 들었을 때 근접 공격 애니메이션
@export var slash_animation := &"sword-slash"
## 서 있을 때 자세로 쓸 애니메이션. 기사 모델에 idle이 없어 이 애니메이션의 첫 프레임에 멈춰 둔다.
@export var idle_pose_animation := &"sword-slash"
## 공격 애니메이션 재생 속도 (배)
@export var attack_animation_speed := 1.5
## 애니메이션이 바뀔 때 섞는 시간 (초)
@export var animation_blend := 0.1
## 검을 들고 있는지. 보물상자를 열면 true가 된다.
@export var has_sword := false

var health: float
var is_dead := false

var _target := Vector3.ZERO
var _has_target := false
var _hurt_left := 0.0
var _teleport_invincible_left := 0.0
var _melee_cooldown_left := 0.0
var _missile_cooldown_left := 0.0
var _teleport_cooldown_left := 0.0
var _stand_left := 0.0
var _ignore_held_move := false
var _marker_tween: Tween
var _fan_tween: Tween
var _teleport_tween: Tween
var _attack_animation_left := 0.0

@onready var _model: Node3D = $Model
@onready var _animation_player: AnimationPlayer = $Model/AnimationPlayer
@onready var _sword: Node3D = $Model/KnightRig/Skeleton3D/Hand_R/Sword
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _click_marker: MeshInstance3D = $ClickMarker
@onready var _melee_fan: MeshInstance3D = $MeleeFan
@onready var _teleport_from_ring: MeshInstance3D = $TeleportFromRing
@onready var _teleport_to_ring: MeshInstance3D = $TeleportToRing


func _ready() -> void:
	health = max_health
	add_to_group("player")
	if projectile_parent == null:
		projectile_parent = get_parent()
	# 바닥에 남는 이펙트는 플레이어를 따라다니지 않도록 월드 기준으로 둔다.
	for effect in [_click_marker, _teleport_from_ring, _teleport_to_ring]:
		effect.top_level = true
	_melee_fan.mesh = _build_fan_mesh()
	_sword.visible = has_sword
	_add_idle_animation()
	_animation_player.play(&"player/idle")
	_prewarm_effects()


## 보물상자가 열리면 불린다. 검을 손에 들고, 근접 공격이 칼질로 바뀐다.
func equip_sword() -> void:
	has_sword = true
	_sword.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event.is_action_pressed("move"):
		var point = get_mouse_ground_point()
		if point != null:
			_ignore_held_move = false
			_set_target(point)
			_show_click_marker(_target)
	elif event.is_action_pressed("teleport"):
		# Space는 누를 때마다 한 번만 발동한다.
		_teleport()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_melee_cooldown_left = maxf(_melee_cooldown_left - delta, 0.0)
	_missile_cooldown_left = maxf(_missile_cooldown_left - delta, 0.0)
	_teleport_cooldown_left = maxf(_teleport_cooldown_left - delta, 0.0)
	_teleport_invincible_left = maxf(_teleport_invincible_left - delta, 0.0)
	_stand_left = maxf(_stand_left - delta, 0.0)
	_attack_animation_left = maxf(_attack_animation_left - delta, 0.0)
	_update_hurt_blink(delta)

	# 우클릭과 Q는 누르고 있으면 쿨다운마다 반복 발동한다.
	if Input.is_action_pressed("attack_melee") and _melee_cooldown_left <= 0.0:
		_melee_attack(get_cursor_direction())
	if Input.is_action_pressed("cast_missile") and _missile_cooldown_left <= 0.0:
		_cast_missile(get_cursor_direction())
	if not Input.is_action_pressed("move"):
		_ignore_held_move = false

	# 공격 직후에는 잠깐 제자리에 선다.
	if _stand_left > 0.0:
		velocity = Vector3.ZERO
		_update_animation(false)
		return

	var wasd := _get_wasd_direction()
	if wasd != Vector3.ZERO:
		_has_target = false
	elif Input.is_action_pressed("move") and not _ignore_held_move:
		# 누르고 있으면 커서를 계속 따라간다.
		var point = get_mouse_ground_point()
		if point != null:
			_set_target(point)

	var direction := wasd
	if direction == Vector3.ZERO and _has_target:
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() <= stop_distance:
			_has_target = false
		else:
			direction = to_target.normalized()

	velocity = direction * move_speed
	move_and_slide()
	if direction != Vector3.ZERO:
		Movement.slide_around_trees(self, direction, move_speed, stuck_ratio)
		_face(direction, delta)
	_update_animation(direction != Vector3.ZERO)


func take_damage(amount: float, _from_position: Vector3) -> void:
	if is_dead or _hurt_left > 0.0 or _teleport_invincible_left > 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die()
		return
	_hurt_left = hurt_invincible_time


## 카메라에서 마우스 위치로 광선을 쏴 바닥(y = 0)과 만나는 점. 못 만나면 null.
func get_mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	return Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)


## 커서 쪽 바닥 방향. 커서를 못 구하면 지금 바라보는 방향.
func get_cursor_direction() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var point = get_mouse_ground_point()
	if point == null:
		return forward
	return Movement.flat_direction(global_position, point, forward)


func _melee_attack(direction: Vector3) -> void:
	_begin_attack(direction)
	_melee_cooldown_left = melee_cooldown
	skill_used.emit(Skill.MELEE, melee_cooldown)

	# Area3D 없이 거리와 각도만으로 판정한다.
	var half_angle := deg_to_rad(melee_angle * 0.5)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.is_dead():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		if offset.length() > melee_range:
			continue
		if offset.length() > 0.001 and direction.angle_to(offset) > half_angle:
			continue
		enemy.take_damage(melee_damage, global_position, melee_knockback)

	_play_attack_animation(slash_animation if has_sword else punch_animation)
	_show_melee_fan()


func _cast_missile(direction: Vector3) -> void:
	_begin_attack(direction)
	_missile_cooldown_left = missile_cooldown
	skill_used.emit(Skill.MISSILE, missile_cooldown)
	_play_attack_animation(punch_animation)

	var missile := missile_scene.instantiate()
	missile.direction = direction
	missile.position = global_position + direction * missile_spawn_forward + Vector3.UP * missile_spawn_height
	projectile_parent.add_child(missile)


## 커서 방향으로 최대 4 m 순간이동. 도착점이 나무·맵 밖이면 발동하지 않고 쿨다운도 쓰지 않는다.
func _teleport() -> void:
	var point = get_mouse_ground_point()
	if point != null:
		_teleport_toward(point)


func _teleport_toward(point: Vector3) -> void:
	if _teleport_cooldown_left > 0.0:
		return
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return
	offset = offset.limit_length(teleport_distance)
	var destination := global_position + offset
	if not _can_stand_at(destination):
		return

	var from := global_position
	global_position = destination
	reset_physics_interpolation()
	rotation.y = atan2(-offset.x, -offset.z)
	_has_target = false
	_teleport_cooldown_left = teleport_cooldown
	_teleport_invincible_left = teleport_invincible_time
	skill_used.emit(Skill.TELEPORT, teleport_cooldown)
	_show_teleport_rings(from, destination)


## 플레이어 몸(캡슐)을 그 자리에 놓아 나무·벽과 겹치는지 본다. 맵 밖이면 false.
func _can_stand_at(point: Vector3) -> bool:
	if absf(point.x) > map_half_size or absf(point.z) > map_half_size:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape.shape
	query.transform = Transform3D(Basis(), point + _collision_shape.position)
	query.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## 공격을 발동하면 이동을 멈추고 커서 쪽으로 몸을 돌린 뒤 잠깐 제자리에 선다.
func _begin_attack(direction: Vector3) -> void:
	rotation.y = atan2(-direction.x, -direction.z)
	_has_target = false
	# 누르고 있던 좌클릭은 무시하고, 다음 좌클릭부터 다시 걷는다.
	_ignore_held_move = Input.is_action_pressed("move")
	_stand_left = attack_stand_time
	velocity = Vector3.ZERO


func _set_target(point: Vector3) -> void:
	_target = Vector3(
		clampf(point.x, -map_half_size, map_half_size),
		0.0,
		clampf(point.z, -map_half_size, map_half_size))
	_has_target = true


## WASD를 화면 기준 방향으로 바꾼다 (W = 화면 위쪽, D = 화면 오른쪽).
func _get_wasd_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d()
	var right := camera.global_basis.x
	var forward := -camera.global_basis.z
	right.y = 0.0
	forward.y = 0.0
	var direction := right.normalized() * input.x - forward.normalized() * input.y
	return direction.normalized()


func _face(direction: Vector3, delta: float) -> void:
	# 앞쪽은 -Z 방향(기사 얼굴이 보는 쪽)이다.
	var yaw := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-turn_speed * delta))


func _update_hurt_blink(delta: float) -> void:
	if _hurt_left <= 0.0:
		return
	_hurt_left = maxf(_hurt_left - delta, 0.0)
	_model.visible = _hurt_left <= 0.0 or int(_hurt_left / blink_interval) % 2 == 0


## 움직이면 달리기, 서 있으면 서 있는 자세. 공격 애니메이션은 끝날 때까지 두되,
## 다시 걷기 시작하면 달리기로 바꾼다.
func _update_animation(moving: bool) -> void:
	var next := &""
	if moving:
		_attack_animation_left = 0.0
		next = &"player/run"
	elif _attack_animation_left <= 0.0:
		next = &"player/idle"
	if next != &"" and _animation_player.current_animation != next:
		_animation_player.play(next, animation_blend)


func _play_attack_animation(animation: StringName) -> void:
	_animation_player.play(animation, animation_blend, attack_animation_speed)
	# 같은 공격을 연달아 쓰면 처음부터 다시 재생한다.
	_animation_player.seek(0.0, true)
	_attack_animation_left = _animation_player.get_animation(animation).length / attack_animation_speed


## 기사 모델에는 idle이 없어서, idle_pose_animation의 첫 프레임만 남긴 애니메이션을 만든다.
## run도 같은 라이브러리에 두어 이름을 한곳에서 관리한다.
func _add_idle_animation() -> void:
	var idle := _animation_player.get_animation(idle_pose_animation).duplicate(true) as Animation
	for track in idle.get_track_count():
		for key in range(idle.track_get_key_count(track) - 1, 0, -1):
			idle.track_remove_key(track, key)
	idle.length = 0.1
	idle.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation(&"idle", idle)
	library.add_animation(&"run", _animation_player.get_animation(run_animation))
	_animation_player.add_animation_library(&"player", library)


## 쓰러지면 회색으로 변하며 옆으로 눕는다.
func _die() -> void:
	is_dead = true
	_hurt_left = 0.0
	_has_target = false
	velocity = Vector3.ZERO
	collision_layer = 0
	_model.visible = true
	_animation_player.pause()
	var gray := StandardMaterial3D.new()
	gray.albedo_color = Color(0.5, 0.5, 0.5)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = gray
	died.emit()
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_parallel()
	tween.tween_property(self, "rotation:z", PI * 0.5, 0.3)
	tween.tween_property(self, "position:y", 0.3, 0.3)


func _show_click_marker(point: Vector3) -> void:
	if _marker_tween:
		_marker_tween.kill()
	_click_marker.global_position = Vector3(point.x, 0.02, point.z)
	_click_marker.reset_physics_interpolation()
	_click_marker.scale = Vector3.ONE
	_set_effect_alpha(_click_marker, 1.0)
	_click_marker.visible = true
	_marker_tween = create_tween().set_parallel()
	_marker_tween.tween_property(_click_marker.material_override, "albedo_color:a", 0.0, click_marker_time)
	_marker_tween.tween_property(_click_marker, "scale", Vector3.ONE * 0.5, click_marker_time)
	_marker_tween.chain().tween_callback(_click_marker.hide)


func _show_melee_fan() -> void:
	if _fan_tween:
		_fan_tween.kill()
	_set_effect_alpha(_melee_fan, 0.6)
	_melee_fan.visible = true
	_fan_tween = create_tween()
	_fan_tween.tween_property(_melee_fan.material_override, "albedo_color:a", 0.0, melee_effect_time)
	_fan_tween.tween_callback(_melee_fan.hide)


func _show_teleport_rings(from: Vector3, to: Vector3) -> void:
	if _teleport_tween:
		_teleport_tween.kill()
	_teleport_from_ring.global_position = Vector3(from.x, 0.03, from.z)
	_teleport_to_ring.global_position = Vector3(to.x, 0.03, to.z)
	for ring in [_teleport_from_ring, _teleport_to_ring]:
		ring.reset_physics_interpolation()
		ring.visible = true
	# 두 원은 머티리얼 하나를 같이 쓰므로 함께 사라진다.
	_set_effect_alpha(_teleport_from_ring, 0.8)
	_teleport_tween = create_tween()
	_teleport_tween.tween_property(_teleport_from_ring.material_override, "albedo_color:a", 0.0, teleport_effect_time)
	_teleport_tween.tween_callback(_teleport_from_ring.hide)
	_teleport_tween.tween_callback(_teleport_to_ring.hide)


## 이펙트는 각자 머티리얼 하나를 계속 재사용하고 알파값만 바꿔 사라지게 한다.
## (GL Compatibility 렌더러에서는 GeometryInstance3D.transparency가 적용되지 않는다.)
func _set_effect_alpha(effect: MeshInstance3D, alpha: float) -> void:
	var material := effect.material_override as StandardMaterial3D
	material.albedo_color.a = alpha


## 사거리·각도에 맞는 부채꼴 메시를 한 번만 만든다 (앞쪽 = -Z).
func _build_fan_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_angle := deg_to_rad(melee_angle * 0.5)
	var segments := 16
	for i in segments:
		var a0 := lerpf(-half_angle, half_angle, float(i) / segments)
		var a1 := lerpf(-half_angle, half_angle, float(i + 1) / segments)
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(Vector3(sin(a1), 0.0, -cos(a1)) * melee_range)
		surface.add_vertex(Vector3(sin(a0), 0.0, -cos(a0)) * melee_range)
	return surface.commit()


## 첫 사용 때 셰이더 컴파일로 멈추지 않도록 시작할 때 한 번 그려 둔다.
func _prewarm_effects() -> void:
	var effects: Array[MeshInstance3D] = [_click_marker, _melee_fan, _teleport_from_ring, _teleport_to_ring]
	for effect in effects:
		if effect.top_level:
			effect.global_position = global_position + Vector3(0.0, 0.02, 0.0)
		_set_effect_alpha(effect, 0.01)
		effect.visible = true
	# 미사일도 한 발 안 움직이게 띄워 둔다.
	var missile := missile_scene.instantiate()
	missile.monitoring = false
	missile.process_mode = Node.PROCESS_MODE_DISABLED
	missile.position = global_position
	projectile_parent.add_child.call_deferred(missile)
	await get_tree().process_frame
	await get_tree().process_frame
	for effect in effects:
		effect.visible = false
	missile.queue_free()
