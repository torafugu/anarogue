class_name PortableRng
extends RefCounted

const UINT32_MODULUS := 4294967296
const UINT32_MASK := UINT32_MODULUS - 1
const FNV1A_OFFSET_BASIS := 2166136261
const FNV1A_PRIME := 16777619
const ZERO_SEED_FALLBACK := 0x6D2B79F5

var state: int


func _init(seed_value: int) -> void:
	state = seed_value & UINT32_MASK
	if state == 0:
		state = ZERO_SEED_FALLBACK


static func fnv1a_32(value: String) -> int:
	var hash_value := FNV1A_OFFSET_BASIS
	for byte in value.to_utf8_buffer():
		hash_value = ((hash_value ^ byte) * FNV1A_PRIME) & UINT32_MASK
	return hash_value


static func derive_seed(
	scenario_seed: int,
	channel: String,
	depth: int,
	entity_id: String = ""
) -> int:
	var key := "%d:%s:%d" % [scenario_seed, channel, depth]
	if not entity_id.is_empty():
		key += ":%s" % entity_id
	return fnv1a_32(key)


func next_u32() -> int:
	var value := state
	value = (value ^ ((value << 13) & UINT32_MASK)) & UINT32_MASK
	value = (value ^ (value >> 17)) & UINT32_MASK
	value = (value ^ ((value << 5) & UINT32_MASK)) & UINT32_MASK
	state = value
	return value


func randi_range(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum)
	var span := maximum - minimum + 1
	assert(span > 0 and span <= UINT32_MODULUS)
	var threshold := (UINT32_MODULUS - span) % span
	while true:
		var value := next_u32()
		if value >= threshold:
			return minimum + value % span
	return minimum


func chance(numerator: int, denominator: int) -> bool:
	assert(denominator > 0)
	assert(numerator >= 0 and numerator <= denominator)
	if numerator == 0:
		return false
	if numerator == denominator:
		return true
	return self.randi_range(0, denominator - 1) < numerator
