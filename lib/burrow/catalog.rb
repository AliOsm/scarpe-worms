# frozen_string_literal: true

module Burrow
  module Catalog
    # All gameplay values live here; every ID has a server-side implementation.
    DATA = [
      ["rocket", "Pocket rocket", "Launchers", "projectile", 48, 48, -1, "Aim and charge a wind-sensitive rocket. Explodes on the first impact."],
      ["mortar", "Moon mortar", "Launchers", "projectile", 18, 26, 3, "Tap to launch a fixed-power shell. Impact scatters five smaller fragments."],
      ["homing", "Love letter", "Launchers", "homing", 45, 42, 2, "Lock, aim, then charge. Its motor steers after half a second and burns for four seconds."],
      ["grenade", "Tick-tock", "Explosives", "bounce", 52, 50, -1, "Set a 1–5 second fuse, charge and throw. Bounces, rolls and blasts on the count."],
      ["cluster", "Party popper", "Explosives", "cluster", 30, 34, 3, "A timed bouncing shell scatters five small impact bomblets. Set a 1–5 second fuse."],
      ["sticky", "Velcro bomb", "Explosives", "sticky", 60, 52, 2, "Sticks to terrain or a grub until its 1–5 second fuse expires. Broken support releases it."],
      ["dynamite", "Short fuse", "Explosives", "place", 78, 72, 2, "Place a charge at your feet. Fixed four-second fuse: move away immediately."],
      ["mega_bomb", "Big trouble", "Explosives", "bounce", 95, 92, 1, "A heavy bouncing bomb with a huge blast. Set a 1–5 second fuse and leave room to retreat."],
      ["banana", "Fruit salad", "Explosives", "cluster", 55, 58, 1, "A bouncy fruit bursts into six smaller impact fruits. Fire splits it before its fuse expires."],
      ["holy_bomb", "Choir bomb", "Explosives", "bounce", 85, 84, 1, "Five seconds, then rest, a short chord and a huge blast. Keeps falling while it waits."],
      ["shotgun", "Double tap", "Direct", "shotgun", 26, 9, -1, "Two separate shots. Re-aim before the second."],
      ["rifle", "Long goodbye", "Direct", "beam", 42, 8, 3, "A precise single shot. Terrain blocks the bullet."],
      ["minigun", "Peashooter", "Direct", "burst", 9, 8, 2, "Eight rounds spread around your aim, chewing small holes."],
      ["laser", "Sunbeam", "Direct", "laser", 38, 12, 2, "A straight beam cuts through terrain and enemies."],
      ["flamethrower", "Hot breath", "Direct", "flame", 8, 15, 2, "A short cone of fire leaves burning ground behind."],
      ["fire_punch", "Uppercrust", "Close-up", "melee", 35, 20, -1, "A close-range uppercut that launches an opponent."],
      ["dragon_punch", "Dragon dash", "Close-up", "dash", 42, 26, 2, "Burst forward through a short tunnel, striking everyone ahead."],
      ["prod", "Little nudge", "Close-up", "melee", 0, 0, -1, "No damage. Plenty of shove. Best beside the water."],
      ["bat", "Home run", "Close-up", "melee", 32, 0, 2, "Aim the angle of an enormous knockback."],
      ["axe", "Half measure", "Close-up", "melee", 0, 0, 2, "Halves a nearby opponent's current health."],
      ["airstrike", "Special delivery", "Sky", "strike", 32, 38, 2, "Choose the approach with ← → and click a target. A passing bomber releases five impact bombs."],
      ["mine_strike", "Rain check", "Sky", "mines", 38, 36, 1, "Choose an approach and target. Five dropped mines arm after landing and remain as traps."],
      ["napalm", "Spicy forecast", "Sky", "napalm", 20, 32, 1, "Choose an approach and target. Five firebombs spread loose flames that burn for 3–5 seconds."],
      ["meteor", "Bad astronomy", "Sky", "meteor", 55, 66, 1, "Call six flaming meteors in a staggered shower across the battlefield. Keep clear of open sky."],
      ["earthquake", "Rumble button", "Sky", "quake", 12, 0, 1, "Shakes grubs off ropes and throws loose props. Frozen grubs stay safe; watch the edges."],
      ["sheep", "Woolly menace", "Critters", "walker", 68, 64, 2, "Release a hopping runner. Fire again explodes it; its fuse lasts eight seconds."],
      ["super_sheep", "Captain wool", "Critters", "guided", 72, 62, 1, "Release, Fire to fly, then Fire to explode. ← / → or A / D steers; eight seconds of flight."],
      ["mole", "Tunnel buddy", "Critters", "digger", 58, 52, 2, "Release, Fire to dive and dig, then Fire to explode. Grubs and tunnel exits also detonate."],
      ["skunk", "Stink express", "Critters", "poisoner", 12, 40, 2, "Release, then Fire for four seconds of running poison spray and a small final blast."],
      ["cow", "Cattle call", "Critters", "herd", 48, 46, 1, "Three runners released one after another; walls and grubs set them off."],
      ["mine", "Mind your step", "Hazards", "mine", 48, 44, 3, "Arms after one second, then reacts to nearby grubs."],
      ["turret", "Sentry sprout", "Hazards", "turret", 16, 8, 1, "A five-shot sentry fires at enemies within sight."],
      ["barrel", "Red barrel", "Hazards", "barrel", 62, 56, 2, "An explosive obstacle. Blasts can start a chain reaction."],
      ["rope", "Grapple line", "Mobility", "rope", 0, 0, 4, "Aim in any direction except straight down. The hook catches the first solid surface; A/D swings, W/S reels, Fire releases."],
      ["jetpack", "Personal cloud", "Mobility", "jetpack", 0, 0, 2, "W/↑ thrusts and A/D or ←/→ strafe. Release keys to save five seconds of fuel; Fire opens a parachute."],
      ["parachute", "Soft landing", "Mobility", "parachute", 0, 0, 2, "Space equips a canopy that opens whenever you fall this turn. A/D steers; open canopies prevent fall damage."],
      ["teleport", "Here to there", "Mobility", "teleport", 0, 0, 2, "Choose clear ground; a red marker means the host will reject the landing. Uses the turn."],
      ["girder", "Bridge builder", "Tools", "girder", 0, 0, 3, "Tilt with ← →, then click open space. Red preview segments are blocked; a 140-pixel beam becomes ground."],
      ["drill", "Down we go", "Tools", "drill", 20, 24, 2, "Bore downward for two seconds. Fire again stops early."],
      ["blowtorch", "Side hustle", "Tools", "torch", 24, 28, 2, "Dig forward; Up / Down changes slope. Fire again stops early."],
      ["heal", "First aid", "Supplies", "heal", 35, 0, 2, "Restore 35 health and clear poison. Uses the turn."],
      ["shield", "Bubble wrap", "Supplies", "shield", 0, 0, 1, "Halve incoming damage until your next turn."],
      ["freeze", "Ice break", "Supplies", "freeze", 0, 0, 1, "Protect your whole team until its next turn. Uses the turn."],
      ["poison", "Stink bomb", "Explosives", "gas", 10, 58, 2, "Set a 1–5 second fuse and throw. A bouncing canister releases drifting, nonlethal poison."],
      ["double_damage", "Extra spicy", "Supplies", "boost", 0, 0, 1, "Double the damage of the attack you make this turn."],
      ["low_gravity", "Moon boots", "Supplies", "gravity", 0, 0, 1, "Reduce gravity for the rest of this turn."],
      ["wind_control", "Weather vane", "Supplies", "wind", 0, 0, 1, "Reverse and double the wind, up to storm strength, for this turn."],
      ["skip", "Pass the turn", "Supplies", "skip", 0, 0, -1, "Let the next team take its turn."]
    ].freeze
    WEAPONS = DATA.to_h do |id, name, group, kind, damage, radius, ammo, description|
      [id, {id: id, name: name, group: group, kind: kind, damage: damage, radius: radius, ammo: ammo, description: description}.freeze]
    end.freeze
    GROUPS = DATA.map { |row| row[2] }.uniq.freeze
    TARGETED = %w[homing strike mines napalm teleport girder].freeze
    UTILITY = %w[rope jetpack parachute shield boost gravity wind].freeze
    SKY = %w[strike mines napalm meteor].freeze
    CHARGED = %w[projectile bounce cluster sticky homing gas].freeze
    FUSED = %w[grenade cluster sticky mega_bomb banana poison].freeze
    AIMED = (CHARGED + %w[shotgun beam laser burst flame melee dash rope]).freeze
    CLASSIC = %w[rocket grenade cluster dynamite shotgun rifle fire_punch prod bat airstrike sheep mine rope parachute teleport girder heal skip].freeze

    def self.fetch(id) = WEAPONS.fetch(id) { raise RuleError, "Choose a weapon from the arsenal." }
    def self.charged?(id) = id != "mortar" && CHARGED.include?(fetch(id)[:kind])

    def self.hint(id)
      kind = fetch(id)[:kind]
      return "Aim · tap Space or click · fixed launch power" if id == "mortar"
      return "Step 1: click to lock a target · Step 2: aim, hold Space or the mouse, release to launch" if kind == "homing"
      return "Click open space to build · ← → tilts the beam · red means blocked" if kind == "girder"
      return "Click the target · ← → picks the bombers' approach" if %w[strike mines napalm].include?(kind)
      return "Aim · hold Space or mouse, release to throw · 1–5 sets fuse · Space mid-air splits it" if id == "banana"
      return "Place with Space or click · fixed 4s fuse · A / D and W to retreat" if id == "dynamite"
      return "Aim · hold Space or mouse, release to throw · fixed 5s, then rest and a short chord" if id == "holy_bomb"
      return "Tap Space or click · six meteors fall across the map · no target needed" if id == "meteor"
      return "Tap Space or click · shakes every team and loose props · no target needed" if id == "earthquake"
      return "Aim · hold Space or mouse, release to throw · 1–5 sets fuse" if FUSED.include?(id)
      return "Aim · hold Space or mouse, release to launch" if CHARGED.include?(kind)
      return fetch(id)[:description] if %w[walker guided digger poisoner herd rope jetpack parachute teleport drill torch].include?(kind)
      return "Click a destination · Space or click deploys" if TARGETED.include?(kind)
      return "Aim · tap Space or click to fire · re-aim for your second shot" if kind == "shotgun"
      return "Aim · tap Space or click to fire" if AIMED.include?(kind)
      "Face your destination · tap Space or click to use"
    end

    def self.inventory(scheme, overrides = {})
      WEAPONS.to_h do |id, weapon|
        count = scheme == "classic" && !CLASSIC.include?(id) ? 0 : weapon[:ammo]
        count = -1 if scheme == "sandbox"
        [id, overrides.fetch(id, count)]
      end
    end
  end
end
