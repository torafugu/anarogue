# These rules override the default AI, including its automatic healing.
# Put a healing rule first if you want it to take priority over shooting.
rule "Recover below 35%" {
  when self.hp_percent <= 35 and self.potions > 0
  do use_potion
}

rule "Counter Archer" {
  target nearest enemy where type == archer and shootable
  when self.weapon == bow
  do shoot target
}

# If no rule is executable, the default strategy handles the Turn.
