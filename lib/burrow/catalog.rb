# frozen_string_literal: true

module Burrow
  module Catalog
    # All gameplay values live here; every ID has a server-side implementation.
    DATA = [
      ["rocket", "Pocket rocket", "Launchers", "projectile", 48, 48, -1, "Wind bends its flight. Point, charge, and let it fly."],
      ["mortar", "Moon mortar", "Launchers", "projectile", 18, 26, 3, "A fixed-power shell bursts on impact into five fragments."],
      ["homing", "Love letter", "Launchers", "homing", 45, 42, 2, "Click a destination. The rocket steers toward it after launch."],
      ["grenade", "Tick-tock", "Explosives", "bounce", 52, 50, -1, "Bounces until the fuse expires. Set a 1–5 second fuse."],
      ["cluster", "Party popper", "Explosives", "cluster", 30, 34, 3, "A bouncing shell that scatters five explosive fragments."],
      ["sticky", "Velcro bomb", "Explosives", "sticky", 60, 52, 2, "Sticks to the first surface it touches. Mind the fuse."],
      ["dynamite", "Short fuse", "Explosives", "place", 78, 72, 2, "Drop it at your feet, then use your retreat time."],
      ["mega_bomb", "Big trouble", "Explosives", "bounce", 95, 92, 1, "A very large bouncing bomb. Your friends may object."],
      ["banana", "Fruit salad", "Explosives", "cluster", 55, 58, 1, "One fruit becomes six. Each piece packs a punch."],
      ["holy_bomb", "Choir bomb", "Explosives", "bounce", 85, 84, 1, "A weighty bomb with a five-second fuse and a grand finale."],
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
      ["airstrike", "Special delivery", "Sky", "strike", 32, 38, 2, "Click a target for five falling bombs. Unavailable in caverns."],
      ["mine_strike", "Rain check", "Sky", "mines", 38, 36, 1, "Drops five persistent proximity mines from above."],
      ["napalm", "Spicy forecast", "Sky", "napalm", 20, 32, 1, "A line of firebombs spreads persistent fire."],
      ["meteor", "Bad astronomy", "Sky", "meteor", 55, 66, 1, "A scattered shower of six destructive meteors."],
      ["earthquake", "Rumble button", "Sky", "quake", 12, 0, 1, "Shakes everyone loose. Watch the edges."],
      ["sheep", "Woolly menace", "Critters", "walker", 68, 64, 2, "A hopping runner. Press Fire again to detonate early."],
      ["super_sheep", "Captain wool", "Critters", "guided", 72, 62, 1, "Release, then Fire to fly. Left / Right steers; Fire again drops it."],
      ["mole", "Tunnel buddy", "Critters", "digger", 58, 52, 2, "Release, Fire to dive and dig, then Fire again to detonate."],
      ["skunk", "Stink express", "Critters", "poisoner", 12, 40, 2, "Release, then Fire to spray poison as it runs."],
      ["cow", "Cattle call", "Critters", "herd", 48, 46, 1, "Three walking troublemakers, released one after another."],
      ["mine", "Mind your step", "Hazards", "mine", 48, 44, 3, "Arms after one second, then reacts to nearby grubs."],
      ["turret", "Sentry sprout", "Hazards", "turret", 16, 8, 1, "A five-shot sentry fires at enemies within sight."],
      ["barrel", "Red barrel", "Hazards", "barrel", 62, 56, 2, "An explosive obstacle. Blasts can start a chain reaction."],
      ["rope", "Grapple line", "Mobility", "rope", 0, 0, 4, "Click ground above to attach. Left / Right swings; Up / Down reels; Fire releases."],
      ["jetpack", "Personal cloud", "Mobility", "jetpack", 0, 0, 2, "Four seconds of thrust. Arrows fly; Fire stops. Fuel only burns while thrusting."],
      ["parachute", "Soft landing", "Mobility", "parachute", 0, 0, 2, "Slows this turn's falls and prevents fall damage."],
      ["teleport", "Here to there", "Mobility", "teleport", 0, 0, 2, "Click clear ground to relocate. Uses the turn."],
      ["girder", "Bridge builder", "Tools", "girder", 0, 0, 3, "Click open space to build a 140-pixel bridge. Uses the turn."],
      ["drill", "Down we go", "Tools", "drill", 20, 24, 2, "Bore downward for two seconds. Fire again stops early."],
      ["blowtorch", "Side hustle", "Tools", "torch", 24, 28, 2, "Dig forward; Up / Down changes slope. Fire again stops early."],
      ["heal", "First aid", "Supplies", "heal", 35, 0, 2, "Restore 35 health and clear poison. Uses the turn."],
      ["shield", "Bubble wrap", "Supplies", "shield", 0, 0, 1, "Halve incoming damage until your next turn."],
      ["freeze", "Ice break", "Supplies", "freeze", 0, 0, 1, "Protect your whole team until its next turn. Uses the turn."],
      ["poison", "Stink bomb", "Explosives", "gas", 10, 58, 2, "A bouncing canister leaves a lingering poison cloud."],
      ["double_damage", "Extra spicy", "Supplies", "boost", 0, 0, 1, "Double the damage of the attack you make this turn."],
      ["low_gravity", "Moon boots", "Supplies", "gravity", 0, 0, 1, "Reduce gravity for the rest of this turn."],
      ["wind_control", "Weather vane", "Supplies", "wind", 0, 0, 1, "Reverse and double the wind, up to storm strength, for this turn."],
      ["skip", "Pass the turn", "Supplies", "skip", 0, 0, -1, "Let the next team take its turn."]
    ].freeze
    WEAPONS = DATA.to_h do |id, name, group, kind, damage, radius, ammo, description|
      [id, {id: id, name: name, group: group, kind: kind, damage: damage, radius: radius, ammo: ammo, description: description}.freeze]
    end.freeze
    GROUPS = DATA.map { |row| row[2] }.uniq.freeze
    TARGETED = %w[homing strike mines napalm rope teleport girder].freeze
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
      return "Click to lock target · aim separately · hold Space, release to launch" if kind == "homing"
      return "Aim · hold Space or mouse, release to throw · 1–5 sets fuse" if FUSED.include?(id)
      return "Aim · hold Space or mouse, release to launch" if CHARGED.include?(kind)
      return fetch(id)[:description] if %w[walker guided digger poisoner herd rope jetpack drill torch].include?(kind)
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
