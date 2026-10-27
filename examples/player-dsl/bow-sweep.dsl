# Use Cautious to prefer Bow equipment. Before acquiring Bow, use default AI.
# Each chosen action consumes one turn; enemies act after it.
rule "Recover" {
  when self.hp_percent <= 35 and self.potions > 0
  do use_potion
}

rule "Keep Bow distance" {
  target nearest enemy
  when self.weapon == bow
  do keep_distance target min = 3 max = 5
}

rule "Shoot" {
  target nearest enemy where shootable
  when self.weapon == bow
  do shoot target
}

# If movement and shooting are blocked, do not fall back to looting/descending.
# This deliberately waits and can reach the Turn limit when enemies are unreachable.
rule "Continue clearing" {
  when self.weapon == bow and floor.enemy_count > 0
  do wait
}

rule "Collect after clearing" {
  target nearest item where distance > 0
  when self.weapon == bow and floor.enemy_count == 0
  do move_toward target
}

rule "Descend after collection" {
  target nearest stairs
  when self.weapon == bow and floor.enemy_count == 0
  do move_toward target
}
