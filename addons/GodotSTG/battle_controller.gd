class_name BattleController extends Node2D

@export_category("BattleController")
@export var stats:STGStats

var life:int
var shield_state:int
var tree:SceneTree
var timer:Timer
var is_spell_over:bool
var flag:int = 0

var hp_threshold:int
var time_threshold:int

var player:Node2D
var enemy:Node2D
var arena_rect:Rect2

func _ready():
	tree = get_tree()
	timer = Timer.new()
	timer.one_shot = true
	STGGlobal.end_sequence.connect(Callable(self, "_on_end_sequence"))
	timer.timeout.connect(Callable(self, "_on_spell_timed_out"))
	STGGlobal.bar_emptied.connect(Callable(self, "_on_bar_emptied"))
	STGGlobal.damage_taken.connect(Callable(self, "_on_damage_taken"))
#	STGGlobal.changed.connect(Callable(self, ))
	add_child(timer)

# TODO: fix this. please.
func start():
	assert(player, "\"player\" has to be set in order for start() to work.")
	assert(enemy, "\"enemy\" has to be set in order for start() to work.")
	assert(arena_rect, "\"arena_rect\" has to be set in order for start() to work.")
	STGGlobal.clear()
	disconnect_stopper()
	STGGlobal.shared_area.reparent(self, false)
	STGGlobal.controller = self
	STGGlobal.battle_start.emit()
	STGGlobal.arena_rect = arena_rect
	var bar_count = stats.bars.size()
	STGGlobal.bar_changed.emit(bar_count)
	life = 0
	player.position = STGGlobal.lerp4arena(stats.player_position)
	for curr_bar in stats.bars:
		emit_life(curr_bar)
		for curr_spell in curr_bar.spells:
			is_spell_over = false
			enemy.position = STGGlobal.lerp4arena(curr_spell.enemy_pos)
			change_shield(curr_spell.shield)
			timer.wait_time = curr_spell.time
			timer.start()
			STGGlobal.spell_name_changed.emit(curr_spell.name)
			enemy.monitoring = true
			cache_spell_textures(curr_spell)
			while !is_spell_over:
				for curr_sequence in curr_spell.sequences:
					if is_spell_over: break
					hp_threshold = curr_sequence.end_at_hp
					time_threshold = curr_sequence.end_at_time
					flag += 1 # timer await is encapsulated in flag increments and decrements
					await tree.create_timer(curr_sequence.wait_before, false).timeout
					flag -= 1 # to prevent running multiple instances at the same time
					if flag: return
					for curr_spawner in curr_sequence.spawners:
						curr_spawner.spawn()
					await STGGlobal.end_sequence
			await STGGlobal.end_spell
			enemy.monitoring = false
		bar_count -= 1
		STGGlobal.bar_changed.emit(bar_count)
	STGGlobal.end_battle.emit()

func cache_spell_textures(spell:STGSpell):
	for seq in spell.sequences:
		for spw in seq.spawners:
			var blt = spw.bullet
			while true:
				STGGlobal.create_texture(blt)
				if !(blt.zoned): break
				blt = blt.zoned

func kill():
	process_mode = Node.PROCESS_MODE_DISABLED
	STGGlobal.clear()
	STGGlobal.shared_area.reparent(STGGlobal, false)
	STGGlobal.stop_spawner.emit()
	STGGlobal.clear()
	queue_redraw()
	await STGGlobal.cleared
	queue_free()

func _physics_process(delta):
	queue_redraw()

func _draw():
	for blt in STGGlobal.b:
		draw_texture(blt.texture, blt.position - blt.texture.get_size() * 0.5)

func emit_life(_bar):
	var values:Array
	var colors:Array
	for i in _bar.spells:
		values.push_front(i.health)
		colors.push_front(i.bar_color)
	STGGlobal.life_changed.emit(values, colors)

func change_shield(_shield:int):
	shield_state = _shield
	STGGlobal.shield_changed.emit(_shield)

func _on_timer_timeout():
	pass

func _on_bar_emptied():
	is_spell_over = true
	STGGlobal.end_sequence.emit()
	STGGlobal.end_spell.emit()
	STGGlobal.stop_spawner.emit()

func _on_spell_timed_out():
	is_spell_over = true
	STGGlobal.end_sequence.emit()
	STGGlobal.end_spell.emit()
	STGGlobal.stop_spawner.emit()

func _on_end_sequence():
	STGGlobal.stop_spawner.emit()
	pass

func _on_damage_taken(_life):
	print(_life)
	if _life <= hp_threshold:
		STGGlobal.end_sequence.emit()
		STGGlobal.stop_spawner.emit()

func disconnect_stopper():
	var arr = STGGlobal.stop_spawner.get_connections()
	for dic in arr:
		STGGlobal.stop_spawner.disconnect(dic.callable)
