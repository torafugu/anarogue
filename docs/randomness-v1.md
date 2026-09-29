# Portable randomness specification v1

This document defines every deterministic random value used by AnaRogue's
simulation. An implementation that follows these integer operations must produce
the same streams in Godot, Rust, and other runtimes.

Random selection of a new scenario seed and random run IDs are metadata concerns
and are outside this contract. Once a `scenario_seed` is supplied, simulation
randomness must follow this specification.

## Integer domain

Seeds and generator outputs are unsigned 32-bit integers from `0` through
`4294967295`. Intermediate values are reduced modulo `2^32`. Rust implementations
should use `u32` and wrapping operations. Godot stores these values in its signed
64-bit `int`, applying the mask `0xffffffff` after every xorshift step.

## Seed derivation

Seed keys use canonical UTF-8 strings with ASCII colon separators:

```text
<scenario_seed>:floor:<depth>
<scenario_seed>:spawn:<depth>
<scenario_seed>:reward:<depth>:<enemy_id>
```

`scenario_seed` and `depth` use unsigned decimal notation without signs or leading
zeros. Current channels are exactly `floor`, `spawn`, and `reward`. Enemy IDs use
their logged form such as `enemy-1`.

Hash the UTF-8 bytes with FNV-1a 32-bit:

```text
hash = 2166136261
for byte in utf8(key):
    hash = hash XOR byte
    hash = (hash * 16777619) modulo 2^32
```

Known results:

| Key | Decimal result | Hex result |
| --- | ---: | ---: |
| empty string | 2166136261 | `0x811c9dc5` |
| `hello` | 1335831723 | `0x4f9f2cab` |
| `424242:floor:1` | 3901461250 | `0xe88b9302` |
| `424242:spawn:1` | 3425048135 | `0xcc261647` |
| `424242:reward:1:enemy-1` | 1039750397 | `0x3df954fd` |

## xorshift32 stream

Each floor, spawn, or enemy reward stream owns an independent xorshift32 state.
If a derived seed is zero, initialize the state to `0x6d2b79f5` instead, because
zero is an absorbing xorshift32 state.

For each output:

```text
x = state
x = x XOR ((x << 13) AND 0xffffffff)
x = x XOR (x >> 17)
x = x XOR ((x << 5) AND 0xffffffff)
state = x AND 0xffffffff
return state
```

The right shift is logical. Since the Godot representation is always a positive
64-bit integer in the u32 range, its right shift has the same result.

The first five outputs for seed `1` are:

```text
270369, 67634689, 2647435461, 307599695, 2398689233
```

The first three outputs for input seed `0`, after zero normalization, are:

```text
1085196063, 2447379481, 2618286376
```

## Inclusive integer range

For an inclusive range `[minimum, maximum]`:

```text
span = maximum - minimum + 1
threshold = (2^32 - span) modulo span
repeat:
    value = next_u32()
until value >= threshold
return minimum + (value modulo span)
```

Rejection avoids modulo bias. For seed `3901461250`, the first ten values in
`[5, 11]` are:

```text
6, 10, 9, 9, 5, 7, 8, 9, 5, 9
```

## Exact probability

Probability checks use an integer fraction, never floating point:

```text
chance(numerator, denominator) =
    range(0, denominator - 1) < numerator
```

Current probabilities are:

| Decision | Probability |
| --- | ---: |
| Horizontal-first corridor | `1/2` |
| Spawn in an intermediate room | `3/4` |
| Spawn a melee enemy | `1/2` |

`chance(0, d)` always returns false and consumes no random value.
`chance(d, d)` always returns true and consumes no random value. All other calls
consume one or more values if bounded-range rejection occurs.

## Stream isolation and consumption order

- A floor stream is created from the floor seed for each depth. It controls room
  width, height, x, y, and corridor orientation in that order.
- A spawn stream is created from the spawn seed for each depth. For each
  intermediate room, it controls spawn presence, x, y, and enemy type in that
  order. Position and type values are consumed only when an enemy is spawned.
- A new reward stream is created for each defeated enemy. Its first bounded value
  in `[1, 4]` is the gold reward.
- Strategy behavior, turn count, and one stream's consumption must never perturb
  another stream.

The executable vectors are in `game/tests/portable_rng_test.gd`.
