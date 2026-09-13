class_name Ship
extends Node3D
## Classic asteroids ship: flat neon arrow, no friction, toroidal wrap.

signal fired(pos: Vector3, dir: Vector3, vel: Vector3)

const ROT_SPEED := 3.6
const THRUST := 50.0
const MAX_SPEED := 100.0
const BULLET_SPEED := 215.0
const FIRE_COOLDOWN := 0.18

var heading := 0.0  # radians in XZ plane; 0 = +X
var velocity := Vector3.ZERO
var alive := false
var autopilot := false
var game: Node = null  # set by main

var _cooldown := 0.0
var _flame: MeshInstance3D = null
var _thrust_snd: AudioStreamPlayer = null

func _ready() -> void:
	_build_visuals()
	_build_audio()

func reset(pos: Vector3, ang: float) -> void:
	position = pos
	heading = ang
	velocity = Vector3.ZERO
	_cooldown = 0.0
	alive = true
	visible = true
	rotation.y = -heading


func heading_dir() -> Vector3:
	return Vector3(cos(heading), 0.0, sin(heading))


func _physics_process(delta: float) -> void:
	if not alive:
		return
	_cooldown = maxf(0.0, _cooldown - delta)

	var want_rot := 0.0
	var want_thrust := false
	var want_fire := false
	if autopilot:
		var d := _autopilot()
		want_rot = d[0]
		want_thrust = d[1]
		want_fire = _autopilot_fire()
	else:
		if Input.is_action_pressed("izquierda"):
			want_rot -= 1.0
		if Input.is_action_pressed("derecha"):
			want_rot += 1.0
		want_thrust = Input.is_action_pressed("adelante")
		want_fire = Input.is_action_pressed("disparar")

	heading += want_rot * ROT_SPEED * delta
	velocity += heading_dir() * THRUST * delta * (1.0 if want_thrust else 0.0)
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	position = G.wrap_pos(position + velocity * delta)
	rotation.y = -heading

	if _flame:
		if want_thrust:
			_flame.visible = true
			_flame.scale = Vector3(randf_range(0.7, 1.3), 1.0, 1.0)
		else:
			_flame.visible = false

	if want_fire and _cooldown <= 0.0:
		_cooldown = FIRE_COOLDOWN
		var dir := heading_dir()
		fired.emit(position + dir * 3.6, dir, velocity + dir * BULLET_SPEED)
		
	if want_thrust and not _thrust_snd.playing:
		_thrust_snd.play()
	else: if not want_thrust and _thrust_snd.playing:
		_thrust_snd.stop()

func _autopilot() -> Array:
	var target_ang := heading
	var thrust := false
	var fleeing := false
	if game and game.rocks:
		var best := Vector3.ZERO
		var bd := INF
		for r in game.rocks:
			if not is_instance_valid(r):
				continue
			var d: Vector3 = r.global_position - global_position
			var l := d.length()
			if l < 28.0 and l < bd:
				bd = l
				best = d
		if bd < INF:
			fleeing = true
			target_ang = atan2(-best.z, -best.x)
		elif global_position.length() > 5.0:
			target_ang = atan2(-global_position.z, -global_position.x)
	var diff := _wrap_angle(target_ang - heading)
	var rot := clampf(diff, -1.0, 1.0)
	if fleeing:
		thrust = absf(diff) < 0.8
	else:
		thrust = absf(diff) < 0.8 and global_position.length() > 3.5
	return [rot, thrust]


func _autopilot_fire() -> bool:
	if _cooldown > 0.0:
		return false
	var h := heading_dir()
	if game:
		for r in game.rocks:
			if not is_instance_valid(r):
				continue
			var d: Vector3 = r.global_position - global_position
			var l := d.length()
			if l < 60.0 and l > 0.0 and h.dot(d / l) > 0.965:
				return true
	return false


static func _wrap_angle(a: float) -> float:
	return fmod(a + PI, TAU) - PI


func _build_visuals() -> void:
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nose := Vector3(3.4, 0.0, 0.0)
	var back_l := Vector3(-2.2, 0.0, 2.3)
	var notch := Vector3(-1.2, 0.0, 0.0)
	var back_r := Vector3(-2.2, 0.0, -2.3)
	for v in [nose, back_l, notch, nose, notch, back_r]:
		st.add_vertex(v)
	st.generate_normals()
	st.commit(mesh)

	var wire := G.unshaded(G.SHIP_COLOR, 2.6)
	var outline := PackedVector3Array([nose, back_l, notch, back_r, nose])
	var wire_mesh := G.lines_mesh(outline, PackedInt32Array([0, 1, 1, 2, 2, 3, 3, 4]))
	var wire_inst := MeshInstance3D.new()
	wire_inst.mesh = wire_mesh
	wire_inst.material_override = wire
	add_child(wire_inst)

	var fill := G.unshaded(G.SHIP_FILL, 0.4)
	var fill_inst := MeshInstance3D.new()
	fill_inst.mesh = mesh
	fill_inst.material_override = fill
	add_child(fill_inst)

	_flame = MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(2.4, 0.5, 0.5)
	_flame.mesh = fm
	_flame.material_override = G.unshaded(G.FLAME_COLOR, 2.2)
	_flame.position = Vector3(-3.6, 0.0, 0.0)
	_flame.visible = false
	add_child(_flame)
	
func _build_audio() -> void:
	_thrust_snd = AudioStreamPlayer.new()
	var wavefile = AudioStreamWAV.load_from_file("res://sounds/trust.wav")
	wavefile.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wavefile.loop_begin = 0
	wavefile.loop_end = wavefile.get_length() * wavefile.mix_rate
	
	_thrust_snd.stream = wavefile
	_thrust_snd.pitch_scale = 1.0
	add_child(_thrust_snd)
	
func stop_sound() -> void:
	_thrust_snd.stop()
