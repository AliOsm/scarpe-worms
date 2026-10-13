# frozen_string_literal: true

module Burrow
  module Catalog
    # All gameplay values live here; every ID has a server-side implementation.
    DATA = [
      ["rocket", "Pocket rocket", "Launchers", "projectile", 48, 48, -1, "Wind bends its flight. Point, charge, and let it fly."],
      ["mortar", "Moon mortar", "Launchers", "projectile", 18, 26, 3, "A fixed-power shell bursts on impact into five fragments."],
      ["homing", "Love letter", "Launchers", "homing", 45, 42, 2, "Lock a target, then aim and charge. The rocket homes in once its motor ignites."],
      ["grenade", "Tick-tock", "Explosives", "bounce", 52, 50, -1, "Bounces until the fuse expires. Set a 1–5 second fuse."],
      ["cluster", "Party popper", "Explosives", "cluster", 30, 34, 3, "A bouncing shell that scatters five explosive fragments."],
      ["sticky", "Velcro bomb", "Explosives", "sticky", 60, 52, 2, "Sticks to the first surface it touches. Mind the fuse."],
      ["dynamite", "Short fuse", "Explosives", "place", 78, 72, 2, "Drop it at your feet, then use your retreat time."],
      ["mega_bomb", "Big trouble", "Explosives", "bounce", 95, 92, 1, "A very large bouncing bomb. Your friends may object."],
      ["banana", "Fruit salad", "Explosives", "cluster", 55, 58, 1, "One fruit becomes six. Press Fire mid-air to split it early."],
      ["holy_bomb", "Choir bomb", "Explosives", "bounce", 85, 84, 1, "A weighty bomb with a five-second fuse and a grand finale."],
      ["shotgun", "Double tap", "Direct", "shotgun", 26, 9, -1, "Two separately aimed pellet shots per cartridge. Finish both before switching."],
      ["rifle", "Long goodbye", "Direct", "beam", 42, 8, 3, "A precise single shot. Terrain blocks the bullet."],
      ["minigun", "Peashooter", "Direct", "burst", 9, 8, 2, "Eight rounds spread around your aim, chewing small holes."],
      ["laser", "Sunbeam", "Direct", "laser", 38, 12, 2, "A straight beam cuts through terrain and enemies."],
      ["flamethrower", "Hot breath", "Direct", "flame", 3, 15, 2, "A short-range stream of fire leaves flames burning on the ground."],
      ["fire_punch", "Uppercrust", "Close-up", "melee", 35, 20, -1, "Leap into a fiery uppercut, launching a nearby opponent upward."],
      ["dragon_punch", "Dragon dash", "Close-up", "dash", 42, 26, 2, "Rush forward through a short tunnel, striking each grub once."],
      ["prod", "Little nudge", "Close-up", "melee", 0, 0, -1, "No damage. Plenty of shove. Best beside the water."],
      ["bat", "Home run", "Close-up", "melee", 32, 0, 2, "Swing at a nearby grub. Your aim sets its enormous launch."],
      ["axe", "Half measure", "Close-up", "melee", 0, 0, 2, "Chop away half a nearby opponent's current health."],
      ["airstrike", "Special delivery", "Sky", "strike", 32, 38, 2, "Pick the approach with ← →, then click a target for five bombs. Not in caverns."],
      ["mine_strike", "Rain check", "Sky", "mines", 38, 36, 1, "Drops five persistent proximity mines from above."],
      ["napalm", "Spicy forecast", "Sky", "napalm", 20, 32, 1, "A line of firebombs spreads persistent fire."],
      ["meteor", "Bad astronomy", "Sky", "meteor", 55, 66, 1, "A scattered shower of six destructive meteors."],
      ["earthquake", "Rumble button", "Sky", "quake", 12, 0, 1, "Shakes everyone loose. Watch the edges."],
      ["sheep", "Woolly menace", "Critters", "walker", 68, 64, 2, "A hopping runner. Press Fire again to detonate early."],
      ["super_sheep", "Captain wool", "Critters", "guided", 72, 62, 1, "Release, then Fire to fly. Left / Right steers; Fire again drops it."],
      ["mole", "Tunnel buddy", "Critters", "digger", 58, 52, 2, "Release, Fire to dive and dig, then Fire again to detonate."],
      ["skunk", "Stink express", "Critters", "poisoner", 12, 40, 2, "Release, then Fire to spray poison as it runs."],
      ["cow", "Cattle call", "Critters", "herd", 48, 46, 1, "Three walking troublemakers, released one after another."],
      ["mine", "Mind your step", "Hazards", "mine", 48, 44, 3, "Place ahead, then retreat. Arms after one second; nearby grubs start its fuse."],
      ["turret", "Sentry sprout", "Hazards", "turret", 16, 8, 1, "Place a five-shot sentry ahead. It tracks enemies within clear sight."],
      ["barrel", "Red barrel", "Hazards", "barrel", 62, 56, 2, "Place an explosive drum ahead. Blasts throw it; rupture spills burning fuel."],
      ["rope", "Grapple line", "Mobility", "rope", 0, 0, 4, "Click ground above to attach. Left / Right swings; Up / Down reels; Fire releases."],
      ["jetpack", "Personal cloud", "Mobility", "jetpack", 0, 0, 2, "Four seconds of thrust. Arrows fly; Fire stops. Fuel only burns while thrusting."],
      ["parachute", "Soft landing", "Mobility", "parachute", 0, 0, 2, "Slows this turn's falls and prevents fall damage."],
      ["teleport", "Here to there", "Mobility", "teleport", 0, 0, 2, "Click clear ground to relocate. Uses the turn."],
      ["girder", "Bridge builder", "Tools", "girder", 0, 0, 3, "Tilt with ← →, then click open space to build a 140-pixel beam. Uses the turn."],
      ["drill", "Down we go", "Tools", "drill", 20, 24, 2, "Bore downward for up to two seconds. Space or click stops early. Uses the turn."],
      ["blowtorch", "Side hustle", "Tools", "torch", 24, 28, 2, "Cut forward for up to two seconds; ↑ / ↓ steers the slope. Space stops early. Uses the turn."],
      ["heal", "First aid", "Supplies", "heal", 35, 0, 2, "Restore 35 health and clear poison. Uses the turn."],
      ["shield", "Bubble wrap", "Supplies", "shield", 0, 0, 1, "Halve this grub's incoming damage until your team's next turn. Keeps your turn."],
      ["freeze", "Ice break", "Supplies", "freeze", 0, 0, 1, "Protect your whole team until its next turn. Uses the turn."],
      ["poison", "Stink bomb", "Explosives", "gas", 10, 58, 2, "A bouncing canister leaves a lingering poison cloud."],
      ["double_damage", "Extra spicy", "Supplies", "boost", 0, 0, 1, "Double your attack damage this turn. Keeps your turn; choose an attack next."],
      ["low_gravity", "Moon boots", "Supplies", "gravity", 0, 0, 1, "Reduce gravity for floaty jumps and shots this turn. Keeps your turn."],
      ["wind_control", "Weather vane", "Supplies", "wind", 0, 0, 1, "Reverse and strengthen this turn's wind. Keeps your turn."],
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
      return "Step 1: click to lock a target · Step 2: aim, hold Space or the mouse, release to launch" if kind == "homing"
      return "Click open space to build · ← → tilts the beam" if kind == "girder"
      return "Click the target · ← → picks the bombers' approach" if %w[strike mines napalm].include?(kind)
      return "Aim · hold Space or mouse, release to throw · 1–5 sets fuse · Space mid-air splits it" if id == "banana"
      return "Aim · hold Space or mouse, release to throw · 1–5 sets fuse" if FUSED.include?(id)
      return "Aim · hold Space or mouse, release to launch" if CHARGED.include?(kind)
      return "Tap Space or click to drill down · Space or click stops early · uses the turn" if kind == "drill"
      return "Face the tunnel · tap Space or click to cut · ↑ / ↓ steers slope · Space stops · uses the turn" if kind == "torch"
      return fetch(id)[:description] if %w[walker guided digger poisoner herd rope jetpack].include?(kind)
      return "Click a destination · Space or click deploys" if TARGETED.include?(kind)
      return "Aim with mouse or ↑ / ↓ · tap Space or click · re-aim and tap for shot two" if kind == "shotgun"
      return "Get close and aim · tap Space or click for a short stream of fire" if kind == "flame"
      return "Aim the launch angle · tap Space or click to swing at a nearby grub" if id == "bat"
      return "Face a nearby grub · tap Space or click to #{id == 'prod' ? 'poke' : id == 'axe' ? 'chop' : 'uppercut'}" if kind == "melee"
      return "Aim left or right · tap Space or click to dash through the ground ahead" if kind == "dash"
      return "Face the placement · tap Space or click to place ahead · retreat with A / D" if %w[mine turret barrel].include?(kind)
      return "Tap Space or click to restore 35 health and cure poison · uses the turn" if kind == "heal"
      return "Tap Space or click to protect this grub · keeps your turn · choose an attack next" if kind == "shield"
      return "Tap Space or click to freeze and protect your team · uses the turn" if kind == "freeze"
      return "Tap Space or click for ×2 attack damage · keeps your turn · choose an attack next" if kind == "boost"
      return "Tap Space or click for low gravity · keeps your turn · W jumps, B backflips" if kind == "gravity"
      return "Tap Space or click to change the wind gauge · keeps your turn" if kind == "wind"
      return "Tap Space or click to end your turn once the battlefield settles" if kind == "skip"
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
