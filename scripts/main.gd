extends Node3D
## Neon Asteroids — main game controller.

enum State { TITLE, PLAY, DYING, GAMEOVER }

const HI_PATH := "user://hi.cfg"
const SHOOT_FRAMES := [90, 240, 480, 720, 1000]

var state := State.TITLE
var score := 0
var hi_score := 0
var lives := 3
var wave := 0

var ship: Ship = null
var rocks: Array = []
var bullets: Array = []

var _auto := false
var _t := 0.0
var _wave_timer := 0.0
var _dying_timer := 0.0
var _msg_hold := 0.0
var _shot_idx := 0
var _frame_count := 0

var _score_label: Label = null
var _hi_label: Label = null
var _wave_label: Label = null
var _lives_label: Label = null
var _msg_label: Label = null
var _sub_label: Label = null

var _fire_snd: AudioStreamPlayer = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_auto = "auto" in args or "-auto" in args
	randomize()
	_build_world()
	_build_hud()
	_load_hi()

	ship = Ship.new()
	add_child(ship)
	ship.game = self
	ship.fired.connect(_on_ship_fired)
	ship.reset(Vector3.ZERO, -PI / 2.0)
	ship.alive = false
	ship.autopilot = _auto
	_build_audio()

	_update_hud()
	_set_message("NEÓN ASTEROIDES", "WASD / FLECHAS — MOVER   ·   ESPACIO — DISPARAR   ·   F12 — CAPTURA", 0.0)
	if _auto:
		_start_game()

func _build_audio() -> void:
	_fire_snd = AudioStreamPlayer.new()
	_fire_snd.volume_linear = 0.2
	_fire_snd.stream = AudioStreamWAV.load_from_file("res://sounds/laserShoot.wav")
	add_child(_fire_snd)

func _play_fire_snd() -> void:
	_fire_snd.stop()
	_fire_snd.pitch_scale = randf_range(0.95, 1.1)
	_fire_snd.play()

func _physics_process(delta: float) -> void:
	_t += delta
	_frame_count += 1

	match state:
		State.TITLE:
			if Input.is_action_pressed("iniciar"):
				_start_game()
		State.PLAY:
			_check_collisions()
			if wave > 0 and rocks.is_empty():
				_wave_timer += delta
				if _wave_timer > 1.2:
					_start_wave(wave + 1)
		State.DYING:
			_dying_timer -= delta
			if _dying_timer <= 0.0:
				if lives > 0:
					ship.reset(Vector3.ZERO, -PI / 2.0)
					state = State.PLAY
				else:
					_save_hi()
					state = State.GAMEOVER
					_set_message("FIN DE LA PARTIDA", "PUNTOS %06d   ·   PULSA ENTER" % score, 9999.0)
		State.GAMEOVER:
			if Input.is_action_pressed("iniciar"):
				_start_game()

	if _msg_hold > 0.0:
		_msg_hold -= delta
		if _msg_hold <= 0.0:
			_msg_label.text = ""
			_sub_label.text = ""

	if (state == State.TITLE or state == State.GAMEOVER) and _sub_label:
		_sub_label.modulate.a = 0.55 + 0.45 * sin(_t * 4.0)
		_sub_label.modulate = Color(1, 1, 1, 0.55 + 0.45 * sin(_t * 4.0))

	if _auto and _frame_count in SHOOT_FRAMES:
		_save_shot()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			_save_shot()


# ------------------------------------------------------------- game flow

func _start_game() -> void:
	score = 0
	lives = 3
	_clear_actors()
	ship.reset(Vector3.ZERO, -PI / 2.0)
	ship.alive = true
	state = State.PLAY
	_set_message("", "", 0.0)
	_start_wave(1)
	_update_hud()


func _start_wave(n: int) -> void:
	wave = n
	_wave_timer = 0.0
	var count := clampi(2 + n, 3, 8)
	for i in count:
		var ang := randf() * TAU
		var dist := 62.0 + randf() * 10.0
		var pos := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var to_center := -pos.normalized()
		var perp := Vector3(-to_center.z, 0.0, to_center.x)
		var side := 1.0 if randf() < 0.5 else -1.0
		var dir := (to_center + perp * side * randf_range(0.25, 0.7)).normalized()
		var speed := randf_range(G.ROCK_SPEEDS[0][0], G.ROCK_SPEEDS[0][1])
		var r := _spawn_rock(0, pos, dir * speed)
		rocks.append(r)
	_set_message("OLEADA %d" % n, "", 1.3)


func _clear_actors() -> void:
	for r in rocks:
		if is_instance_valid(r):
			r.queue_free()
	rocks.clear()
	for b in bullets:
		if is_instance_valid(b):
			b.queue_free()
	bullets.clear()


func _spawn_rock(idx: int, pos: Vector3, v: Vector3) -> Rock:
	var r := Rock.new()
	r.setup(idx, pos, v)
	add_child(r)
	return r


func _destroy_rock(r: Rock, by_bullet: bool) -> void:
	var pos := r.global_position
	var ex := Explosion.new()
	ex.color = G.ROCK_COLORS[r.size_idx]
	ex.scale_mult = r.radius / 4.0
	add_child(ex)
	ex.global_position = pos
	if by_bullet:
		score += G.SCORES[r.size_idx]
		_update_hud()
	if r.size_idx < 2:
		var child_idx := r.size_idx + 1
		for k in 2:
			var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			var speed := randf_range(G.ROCK_SPEEDS[child_idx][0], G.ROCK_SPEEDS[child_idx][1])
			var child := _spawn_rock(child_idx, pos, r.vel * 0.1 + dir * speed)
			rocks.append(child)
	rocks.erase(r)
	r.queue_free()


func _kill_ship() -> void:
	ship.alive = false
	ship.visible = false
	ship.stop_sound()
	lives -= 1
	var ex := Explosion.new()
	ex.color = G.SHIP_COLOR
	ex.scale_mult = 2.0
	add_child(ex)
	ex.global_position = ship.global_position
	_update_hud()
	state = State.DYING
	_dying_timer = 1.5
	if lives > 0:
		_set_message("NAVE PERDIDA", "", 1.4)
	else:
		_set_message("FIN DE LA PARTIDA", "PUNTOS %06d   ·   PULSA ENTER" % score, 9999.0)


func _check_collisions() -> void:
	# Bullets free themselves when their lifetime expires, so the array can
	# hold already-freed instances. Always validate *before* the typed
	# assignment (a typed assign to a freed instance throws), and drop dead
	# entries by index, highest first so earlier indices stay valid.
	var dead_idx: Array = []
	for i in range(bullets.size()):
		if not is_instance_valid(bullets[i]):
			dead_idx.append(i)
			continue
		var b: Bullet = bullets[i]
		for j in range(rocks.size()):
			if not is_instance_valid(rocks[j]):
				continue
			var r: Rock = rocks[j]
			# Swept (segment) test: the bullet moves ~7 u/frame and a small
			# rock's collision pad is only ~2.8 u, so a point test tunnels.
			if _seg_point_hit(b.prev_pos, b.global_position, r.global_position, r.radius + 0.8):
				_destroy_rock(r, true)
				b.queue_free()
				dead_idx.append(i)
				break
	if dead_idx.size() > 0:
		dead_idx.sort()
		for k in range(dead_idx.size() - 1, -1, -1):
			bullets.remove_at(dead_idx[k])

	if ship and ship.alive:
		for r in rocks:
			if not is_instance_valid(r):
				continue
			if ship.global_position.distance_to(r.global_position) < r.radius + G.SHIP_RADIUS:
				_kill_ship()
				break


## Distance from point c to segment a->b (flat space: bullets never wrap, so
## both endpoints stay inside the arena and no seam unwrap is needed).
func _seg_point_hit(a: Vector3, b: Vector3, c: Vector3, pad: float) -> bool:
	var ab := b - a
	var ac := c - a
	var t := clampf(ac.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ac - ab * t).length() <= pad


func _on_ship_fired(pos: Vector3, dir: Vector3, vel: Vector3) -> void:
	if bullets.size() >= 4:
		return
	var b := Bullet.new()
	add_child(b)
	b.launch(pos, dir, vel)
	bullets.append(b)
	_play_fire_snd()


# ------------------------------------------------------------- hud

func _build_hud() -> void:
	# NOTE (Godot 4): `position` is ABSOLUTE in viewport coords, NOT relative
	# to the anchor. Anchored labels must be placed with offsets (which ARE
	# anchor-relative), or they land off-screen. The centered message labels
	# also need anchor_top/bottom = 0.5, otherwise their negative offsets push
	# them above the top edge.
	var layer := CanvasLayer.new()
	add_child(layer)

	# Top-left: score (anchor 0,0 -> position == offset, fine).
	_score_label = _mk_label(layer, "PUNTOS 000000", 22, G.UI_COLOR)
	_score_label.position = Vector2(18, 12)
	_score_label.size = Vector2(320, 40)

	# Top-right: hi-score, pinned to the right edge, growing left.
	_hi_label = _mk_label(layer, "RÉCORD 000000", 22, G.UI_COLOR)
	_hi_label.anchor_left = 1.0
	_hi_label.anchor_right = 1.0
	_hi_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hi_label.offset_left = -280.0
	_hi_label.offset_right = -18.0
	_hi_label.offset_top = 12.0
	_hi_label.offset_bottom = 52.0
	_hi_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Top-center: wave.
	_wave_label = _mk_label(layer, "", 22, G.UI_COLOR)
	_wave_label.anchor_left = 0.5
	_wave_label.anchor_right = 0.5
	_wave_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wave_label.offset_left = -120.0
	_wave_label.offset_right = 120.0
	_wave_label.offset_top = 12.0
	_wave_label.offset_bottom = 52.0
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Bottom-left: lives, pinned to the bottom edge, growing up.
	_lives_label = _mk_label(layer, "▲ ▲ ▲", 18, G.SHIP_COLOR)
	_lives_label.anchor_top = 1.0
	_lives_label.anchor_bottom = 1.0
	_lives_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_lives_label.offset_left = 18.0
	_lives_label.offset_right = 240.0
	_lives_label.offset_top = -52.0
	_lives_label.offset_bottom = -14.0

	# Center: main message (anchors on all four sides, offsets relative).
	_msg_label = _mk_label(layer, "", 46, G.SHIP_COLOR)
	_msg_label.anchor_left = 0.5
	_msg_label.anchor_right = 0.5
	_msg_label.anchor_top = 0.5
	_msg_label.anchor_bottom = 0.5
	_msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_msg_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_msg_label.offset_left = -420.0
	_msg_label.offset_top = -210.0
	_msg_label.offset_right = 420.0
	_msg_label.offset_bottom = -150.0
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Center: sub message (below the main one).
	_sub_label = _mk_label(layer, "", 18, G.UI_COLOR)
	_sub_label.anchor_left = 0.5
	_sub_label.anchor_right = 0.5
	_sub_label.anchor_top = 0.5
	_sub_label.anchor_bottom = 0.5
	_sub_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_sub_label.offset_left = -420.0
	_sub_label.offset_top = -140.0
	_sub_label.offset_right = 420.0
	_sub_label.offset_bottom = -110.0
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _mk_label(parent: CanvasLayer, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = color
	ls.outline_size = 8
	ls.outline_color = Color(0.0, 0.0, 0.05, 0.85)
	l.label_settings = ls
	l.text = text
	parent.add_child(l)
	return l


func _set_message(main_t: String, sub_t: String, hold: float) -> void:
	_msg_label.text = main_t
	_sub_label.text = sub_t
	_msg_hold = hold


func _update_hud() -> void:
	_score_label.text = "PUNTOS %06d" % score
	_hi_label.text = "RÉCORD %06d" % maxi(hi_score, score)
	_wave_label.text = "OLEADA %d" % wave
	_lives_label.text = "▲ ".repeat(lives).strip_edges()


# ------------------------------------------------------------- hi-score

func _load_hi() -> void:
	var cf := ConfigFile.new()
	if cf.load(HI_PATH) == OK:
		var v: Variant = cf.get_value("game", "hi", 0)
		hi_score = v if typeof(v) == TYPE_INT else int(v)


func _save_hi() -> void:
	if score > hi_score:
		hi_score = score
	var cf := ConfigFile.new()
	cf.set_value("game", "hi", hi_score)
	if cf.save(HI_PATH) != OK:
		push_warning("hi.cfg: save failed")


# ------------------------------------------------------------- world

func _build_world() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = G.BG_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.85
	env.glow_bloom = 0.45
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 70.0, 57.0)
	cam.fov = 58.0
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var mat_grid := G.unshaded(G.GRID_COLOR, 1.0)
	var step := 10.0
	for i in 12:
		var off := -G.ARENA_HALF + i * step
		_add_line(Vector3(off, 0.0, -G.ARENA_HALF), Vector3(off, 0.0, G.ARENA_HALF), mat_grid, 0.12)
		_add_line(Vector3(-G.ARENA_HALF, 0.0, off), Vector3(G.ARENA_HALF, 0.0, off), mat_grid, 0.12)

	var mat_frame := G.unshaded(G.FRAME_COLOR, 2.0)
	var h := G.ARENA_HALF
	_add_line(Vector3(-h, 0.0, -h), Vector3(h, 0.0, -h), mat_frame, 0.3)
	_add_line(Vector3(-h, 0.0, h), Vector3(h, 0.0, h), mat_frame, 0.3)
	_add_line(Vector3(-h, 0.0, -h), Vector3(-h, 0.0, h), mat_frame, 0.3)
	_add_line(Vector3(h, 0.0, -h), Vector3(h, 0.0, h), mat_frame, 0.3)

	_build_stars()


func _add_line(a: Vector3, b: Vector3, mat: Material, thick: float) -> void:
	var d := b - a
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(thick, 0.03, d.length())
	mi.mesh = bm
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	mi.rotation.y = atan2(d.x, d.z)
	add_child(mi)


func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260912
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var octa: PackedVector3Array = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0),
		Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
	]
	var octa_faces := [
		[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
		[2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5],
	]
	for i in 420:
		var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.2, 1.2), rng.randf_range(-1.0, 1.0)).normalized()
		var p := dir * rng.randf_range(150.0, 260.0) + Vector3(0.0, -10.0, 0.0)
		var r := rng.randf_range(0.5, 1.6)
		for f in octa_faces:
			st.add_vertex(p + octa[f[0]] * r)
			st.add_vertex(p + octa[f[1]] * r)
			st.add_vertex(p + octa[f[2]] * r)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = G.unshaded(Color(0.75, 0.85, 1.0, 0.9), 1.6)
	add_child(mi)


# ------------------------------------------------------------- screenshots

func _save_shot() -> void:
	# Headless runs have no framebuffer: the dummy rendering server returns a
	# null texture, so get_image() errors and save_png would crash on null.
	if DisplayServer.get_name() == "headless":
		print("SHOT skipped (headless, no framebuffer) frame=", Engine.get_process_frames(), " state=", state)
		return
	var img := get_viewport().get_texture().get_image()
	if img == null:
		print("SHOT failed (null image) frame=", Engine.get_process_frames(), " state=", state)
		return
	var path := "user://auto_%02d.png" % _shot_idx
	img.save_png(path)
	_shot_idx += 1
	print("SHOT ", path, " frame=", Engine.get_process_frames(), " state=", state)
