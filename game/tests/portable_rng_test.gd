extends SceneTree

const PortableRng := preload("res://scripts/portable_rng.gd")

var failures: Array[String] = []


func _init() -> void:
	assert_equal(PortableRng.fnv1a_32(""), 2166136261, "FNV-1a empty string")
	assert_equal(PortableRng.fnv1a_32("hello"), 1335831723, "FNV-1a hello")
	assert_equal(
		PortableRng.derive_seed(424242, "floor", 1),
		3901461250,
		"Floor seed derivation"
	)
	assert_equal(
		PortableRng.derive_seed(424242, "spawn", 1),
		3425048135,
		"Spawn seed derivation"
	)
	assert_equal(
		PortableRng.derive_seed(424242, "reward", 1, "enemy-1"),
		1039750397,
		"Reward seed derivation"
	)

	var rng := PortableRng.new(1)
	assert_equal(
		collect_u32(rng, 5),
		[270369, 67634689, 2647435461, 307599695, 2398689233],
		"xorshift32 sequence for seed 1"
	)

	var zero_rng := PortableRng.new(0)
	assert_equal(
		collect_u32(zero_rng, 3),
		[1085196063, 2447379481, 2618286376],
		"Zero seed normalization"
	)

	var range_rng := PortableRng.new(3901461250)
	assert_equal(
		collect_range(range_rng, 10, 5, 11),
		[6, 10, 9, 9, 5, 7, 8, 9, 5, 9],
		"Inclusive bounded integer sequence"
	)
	var chance_rng := PortableRng.new(3901461250)
	assert_equal(
		collect_chance(chance_rng, 10, 1, 2),
		[false, true, false, false, false, false, true, false, true, true],
		"Exact rational chance sequence"
	)

	finish()


func collect_u32(rng: PortableRng, count: int) -> Array[int]:
	var values: Array[int] = []
	for _index in range(count):
		values.append(rng.next_u32())
	return values


func collect_range(
	rng: PortableRng,
	count: int,
	minimum: int,
	maximum: int
) -> Array[int]:
	var values: Array[int] = []
	for _index in range(count):
		values.append(rng.randi_range(minimum, maximum))
	return values


func collect_chance(
	rng: PortableRng,
	count: int,
	numerator: int,
	denominator: int
) -> Array[bool]:
	var values: Array[bool] = []
	for _index in range(count):
		values.append(rng.chance(numerator, denominator))
	return values


func assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		return
	failures.append("%s: expected %s, got %s" % [label, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("Portable RNG tests passed.")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)
