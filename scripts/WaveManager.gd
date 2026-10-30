class_name WaveManager
extends Node

## 웨이브 구성표대로 스폰 지점에서 적을 하나씩 내보낸다.
## 전멸하면 쉬었다가 다음 웨이브, 마지막 웨이브를 넘기면 all_waves_cleared.

signal wave_started(wave_number: int, wave_count: int)
signal remaining_changed(remaining: int)
signal all_waves_cleared
signal _wave_cleared

## 웨이브 구성표: (근거리, 원거리, 덩치) 마릿수
@export var waves: Array[Vector3i] = [Vector3i(6, 0, 0), Vector3i(6, 3, 0), Vector3i(6, 4, 2)]
@export var melee_scene: PackedScene
@export var ranged_scene: PackedScene
@export var brute_scene: PackedScene
@export var player: Player
## 스폰된 적이 들어갈 노드 (Main의 Enemies)
@export var enemy_parent: Node3D
## 스폰 지점(Marker3D)들의 부모
@export var spawn_points: Node3D
## 게임 시작 후 첫 웨이브까지 (초)
@export var first_wave_delay := 1.0
## 웨이브 사이 쉬는 시간 (초)
@export var rest_time := 3.0
## 적이 하나씩 나오는 간격 (초)
@export var spawn_interval := 0.5
## 플레이어와 이만큼 떨어진 스폰 지점만 쓴다 (m)
@export var min_spawn_distance := 10.0

## 지금 웨이브 번호 (1부터, 시작 전 0)
var current_wave := 0
## 처치 수
var kills := 0
## 경과 시간 (초). 승리하거나 쓰러지면 멈춘다.
var elapsed := 0.0
## 이번 웨이브에서 남은 적 (아직 안 나온 적 포함)
var remaining := 0
var finished := false


func _ready() -> void:
	_prewarm()
	_run()


func _physics_process(delta: float) -> void:
	if not finished and not player.is_dead:
		elapsed += delta


func _run() -> void:
	await _wait(first_wave_delay)
	for i in waves.size():
		current_wave = i + 1
		var spawn_list := _make_spawn_list(waves[i])
		remaining = spawn_list.size()
		wave_started.emit(current_wave, waves.size())
		remaining_changed.emit(remaining)
		for scene in spawn_list:
			if player.is_dead:
				return
			_spawn(scene)
			await _wait(spawn_interval)
		if remaining > 0:
			await _wave_cleared
		if player.is_dead:
			return
		if i < waves.size() - 1:
			await _wait(rest_time)


## 종류를 섞어서 내보낸다.
func _make_spawn_list(counts: Vector3i) -> Array[PackedScene]:
	var spawn_list: Array[PackedScene] = []
	for n in counts.x:
		spawn_list.append(melee_scene)
	for n in counts.y:
		spawn_list.append(ranged_scene)
	for n in counts.z:
		spawn_list.append(brute_scene)
	spawn_list.shuffle()
	return spawn_list


func _spawn(scene: PackedScene) -> void:
	var enemy := scene.instantiate() as Enemy
	enemy.position = _pick_spawn_point()
	enemy.died.connect(_on_enemy_died)
	enemy_parent.add_child(enemy)


## 플레이어와 10 m 이상 떨어진 스폰 지점 중 무작위. 없으면 가장 먼 곳.
func _pick_spawn_point() -> Vector3:
	var candidates: Array[Vector3] = []
	var farthest := Vector3.ZERO
	var farthest_distance := -1.0
	for marker in spawn_points.get_children():
		var point: Vector3 = marker.global_position
		var distance := point.distance_to(player.global_position)
		if distance >= min_spawn_distance:
			candidates.append(point)
		if distance > farthest_distance:
			farthest_distance = distance
			farthest = point
	if candidates.is_empty():
		return farthest
	return candidates.pick_random()


func _on_enemy_died(_enemy: Enemy) -> void:
	kills += 1
	remaining -= 1
	remaining_changed.emit(remaining)
	if remaining > 0:
		return
	if current_wave == waves.size():
		finished = true
		all_waves_cleared.emit()
	_wave_cleared.emit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, false, true).timeout


## 처음 나올 때 셰이더 컴파일로 멈추지 않도록, 게임 시작 때 적 3종과 화살을
## 바닥 아래(카메라에는 잡히지만 땅에 가려지는 곳)에 잠깐 그려 둔다.
func _prewarm() -> void:
	var hidden_spot := player.global_position + Vector3(0.0, -3.0, 0.0)
	var nodes: Array[Node3D] = []
	for scene in [melee_scene, ranged_scene, brute_scene]:
		var enemy := scene.instantiate() as Enemy
		enemy.prewarm = true
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		enemy.position = hidden_spot
		nodes.append(enemy)
		if enemy is RangedEnemy:
			var arrow: Area3D = enemy.arrow_scene.instantiate()
			arrow.monitoring = false
			arrow.process_mode = Node.PROCESS_MODE_DISABLED
			arrow.position = hidden_spot
			nodes.append(arrow)
	for node in nodes:
		enemy_parent.add_child.call_deferred(node)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	for node in nodes:
		node.queue_free()
