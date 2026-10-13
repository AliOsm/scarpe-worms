# frozen_string_literal: true
# Weapon lab: drive each weapon through real native keyboard/pointer input on a
# fixed course and capture frame strips for review.
#
#   SCARPE_DISPLAY_SERVICE=native SCARPE_NATIVE_HEADLESS=1 [BURROW_LAB_WEAPONS="rope jetpack"] ./bin/scarpe tools/weapon_lab.rb
#
# Writes BURROW_LAB_OUT (default .cache/weapon-lab)/<weapon>/frame-NN.png plus a
# log.json of the authoritative state at every capture, and lab.json overall.
# The host runs in this process on loopback TLS; between weapons the course is
# reset inside the host's own tick, so every weapon starts from the same state.
require "tmpdir"
require "stringio"
require "logger"
require_relative "../lib/burrow"
directory = Dir.mktmpdir("burrow-lab-")
ENV["BURROW_DATA_DIR"] = directory
ENV["BURROW_MUTE"] = "1"
require_relative "../lib/burrow/server/reactor"
require_relative "../lib/burrow/server/certificate"

OUT = ENV.fetch("BURROW_LAB_OUT", File.join(Burrow::ROOT, ".cache/weapon-lab"))
GROUND = 900

# The course, in world pixels (2880 x 1280; water at 1184):
#   ground from y 900; a ceiling slab over the player for the grapple;
#   a raised girder perch for drops; a wall beyond the first enemy.
module LabCourse
  def self.terrain(match)
    terrain = match.terrain
    data = "\0".b * (terrain.cols * terrain.rows)
    data[(GROUND / 2) * terrain.cols..] = "\1" * ((terrain.rows - GROUND / 2) * terrain.cols)
    course = Burrow::Terrain.new(seed: terrain.seed, width: terrain.width, height: terrain.height, data: data, revision: terrain.revision + 1)
    course.bridge(560, 430, width: 760, height: 46)   # ceiling slab x 180..940, y 430..476
    course.bridge(1320, 700, width: 40, height: 200)   # wall x 1300..1340
    course.bridge(560, 690, width: 150, height: 12)    # perch x 485..635
    course
  end

  POSITIONS = {"w1" => [300.0, GROUND], "w2" => [760.0, GROUND], "w3" => [160.0, GROUND], "w4" => [1700.0, GROUND]}.freeze

  def step(count = 1)
    if (setup = $lab_reset)
      $lab_reset = nil
      lab_reset(setup)
    end
    super
  end

  # The lab plays every turn itself; the opposing bot never takes a shot.
  def run_bot; end

  def lab_reset(setup)
    @terrain = LabCourse.terrain(self)
    # End every flight on record so the client retires its sprites too.
    (@shot_tracks || {}).each_value { |track| track["to"] ||= tick }
    projectiles.clear
    hazards.clear
    @salvos = []
    @tool = nil
    worms.each do |w|
      x, y = POSITIONS.fetch(w[:id])
      x, y = setup[:at] if w[:id] == "w1" && setup[:at]
      w.merge!(x: x, y: y.to_f, vx: 0.0, vy: 0.0, hp: 100, max_hp: 100, facing: w[:id] == "w1" || w[:id] == "w3" ? 1 : -1,
        rope: nil, fuel: 0, jetpack: false, parachute: false, launched: false, poisoned: false, shield: false, frozen: false,
        input: 0.0, lift: 0.0, input_until: 0)
      w.merge!(setup.fetch(:grub, {})) if w[:id] == "w1"
    end
    teams.each { |t| t[:inventory] = Burrow::Catalog.inventory("sandbox") }
    @team_index = 0
    @active_id = "w1"
    @phase = "aiming"
    @deadline = tick + 90 * Burrow::TICK_RATE
    @shots_left, @shot_weapon, @damage_boost, @low_gravity = 0, nil, false, false
    @wind = setup.fetch(:wind, 0.0)
    if setup[:barrel_blast]
      # A fuse already burning on the course exercises the placed barrel's
      # blast throw, rupture and fuel spill while the player retreats normally.
      bomb = Burrow::Catalog.fetch("mega_bomb")
      projectile(bomb, x: 324, y: GROUND - 8, vx: 0, vy: 0, damage: bomb[:damage],
        life: 5 * Burrow::TICK_RATE, bounce: true, owner: teams[1][:id])
    end
    # Alternate turns 1 and 2: a new turn for the client, never sudden death.
    @turn = @turn == 1 ? 2 : 1
    @bot_at = tick + 1_000_000
    emit("turn", team: team[:id], worm: active_id, text: "Weapon lab")
  end
end
Burrow::Match.prepend(LabCourse)

# Player scripts: what a person does to use each weapon. Positions are world
# points; :aim points the cursor; :charge holds Space; :click is a left click.
ENEMY = [760, GROUND - 12]
SCRIPTS = {
  "rocket" => [[:aim, [760, 690]], [:charge, 0.7], [:wait, 5.0]],
  "mortar" => [[:aim, [700, 560]], [:press, " "], [:wait, 7.0]],
  "homing" => [[:click, ENEMY], [:aim, [380, 560]], [:charge, 0.5], [:press, "f"], [:wait, 10.0]],
  "grenade" => [[:press, "3"], [:aim, [620, 640]], [:charge, 0.5], [:wait, 6.0]],
  "cluster" => [[:press, "3"], [:aim, [620, 600]], [:charge, 0.5], [:wait, 8.0]],
  "sticky" => [[:place, [690, GROUND]], [:press, "3"], [:aim, ENEMY], [:charge, 0.4], [:wait, 6.0]],
  "dynamite" => [[:press, " "], [:hold, "a", 1.2], [:wait, 6.0]],
  "mega_bomb" => [[:press, "3"], [:aim, [620, 640]], [:charge, 0.5], [:wait, 7.0]],
  "banana" => [[:press, "5"], [:aim, [620, 520]], [:charge, 0.5], [:wait, 0.6], [:press, " "], [:wait, 7.0]],
  "holy_bomb" => [[:aim, [620, 640]], [:charge, 0.5], [:wait, 8.0]],
  "poison" => [[:press, "3"], [:aim, [620, 640]], [:charge, 0.55], [:wait, 10.0]],
  "shotgun" => [[:aim, ENEMY], [:press, " "], [:wait, 0.45], [:click, [790, GROUND - 22]], [:wait, 1.4]],
  "rifle" => [[:click, ENEMY], [:wait, 1.4]],
  "minigun" => [[:aim, ENEMY], [:press, " "], [:wait, 1.6]],
  "laser" => [[:click, ENEMY], [:wait, 1.4]],
  "flamethrower" => [[:place, [640, GROUND]], [:aim, ENEMY], [:press, " "], [:wait, 3.8]],
  "fire_punch" => [[:place, [725, GROUND]], [:aim, [800, GROUND - 40]], [:press, " "], [:wait, 2.0]],
  "dragon_punch" => [[:place, [700, GROUND]], [:aim, [800, GROUND - 12]], [:press, " "], [:wait, 2.0]],
  "prod" => [[:place, [730, GROUND]], [:click, [800, GROUND - 12]], [:wait, 1.6]],
  "bat" => [[:place, [730, GROUND]], [:aim, [820, GROUND - 60]], [:press, " "], [:wait, 2.4]],
  "axe" => [[:place, [730, GROUND]], [:click, [800, GROUND - 12]], [:wait, 1.6]],
  "airstrike" => [[:press, "left"], [:click, [1700, GROUND - 10]], [:press, "f"], [:wait, 9.0]],
  "mine_strike" => [[:press, "right"], [:click, [1700, GROUND - 10]], [:press, "f"], [:wait, 10.0]],
  "napalm" => [[:press, "left"], [:click, [1700, GROUND - 10]], [:press, "f"], [:wait, 13.0]],
  "meteor" => [[:press, " "], [:wait, 8.0]],
  "earthquake" => [[:press, " "], [:wait, 6.0]],
  "sheep" => [[:press, " "], [:wait, 3.0], [:click, ENEMY], [:wait, 3.0]],
  "super_sheep" => [[:press, " "], [:wait, 0.2], [:press, " "], [:hold, "left", 0.42], [:wait, 0.1],
    [:hold, "d", 0.55], [:press, " "], [:wait, 1.6]],
  "mole" => [[:press, " "], [:wait, 1.0], [:press, " "], [:wait, 1.4], [:press, " "], [:wait, 1.4]],
  "skunk" => [[:press, " "], [:wait, 1.6], [:press, " "], [:wait, 5.0]],
  "cow" => [[:press, " "], [:wait, 10.0]],
  "mine" => [[:place, [701, GROUND]], [:press, " "], [:hold, "a", 0.8], [:wait, 2.0]],
  "turret" => [[:place, [430, GROUND]], [:click, ENEMY], [:wait, 6.8]],
  "barrel" => [[:setup, {barrel_blast: true}], [:click, [400, GROUND - 12]], [:hold, "a", 1.4], [:wait, 5.0]],
  "rope" => [[:aim, [380, 470]], [:press, " "], [:wait, 0.5], [:hold, "w", 1.2], [:hold, "d", 0.5],
    [:press, "enter"], [:aim, [500, 470]], [:press, " "], [:wait, 0.2], [:hold, "a", 0.2], [:hold, "s", 0.1],
    [:press, " "], [:wait, 1.6]],
  "jetpack" => [[:press, " "], [:wait, 0.2], [:hold, "w", 1.0], [:hold, "d", 0.7], [:hold, "a", 0.4], [:press, " "], [:wait, 2.2]],
  "parachute" => [[:place, [560, 690]], [:press, "w"], [:wait, 0.35], [:press, " "], [:hold, "d", 1.4], [:wait, 2.6]],
  "teleport" => [[:aim, [760, GROUND - 10]], [:wait, 0.3], [:aim, [1100, GROUND - 10]], [:wait, 0.35], [:press, " "], [:wait, 1.6]],
  "girder" => [[:press, "right"], [:aim, [560, 700]], [:wait, 0.3], [:aim, [520, 760]], [:wait, 0.35], [:press, " "], [:wait, 1.2]],
  "drill" => [[:press, " "], [:wait, 0.3], [:press, " "], [:wait, 1.2]],
  "blowtorch" => [[:click, [800, GROUND - 12]], [:hold, "down", 0.03], [:press, " "], [:wait, 1.2]],
  "heal" => [[:setup, {grub: {hp: 65, poisoned: true}}], [:press, " "], [:wait, 1.4]],
  "shield" => [[:click, [400, GROUND - 12]], [:hold, "d", 0.4], [:wait, 1.0]],
  "freeze" => [[:click, [400, GROUND - 12]], [:wait, 1.4]],
  "double_damage" => [[:press, " "], [:wait, 1.2]],
  "low_gravity" => [[:press, " "], [:hold, "w", 0.2], [:wait, 1.6]],
  "wind_control" => [[:setup, {wind: 0.55}], [:press, " "], [:wait, 1.2]],
  "skip" => [[:click, [400, GROUND - 12]], [:wait, 1.2]]
}.freeze

failed = false
summary = {}
at_exit { FileUtils.remove_entry(directory) if File.directory?(directory); exit(1) if failed }
$lab_dir = File.join(directory, "server")
cert, key = Burrow::Server::Certificate.ensure_pair(File.join($lab_dir, "tls"))
$lab_server = Burrow::Server::Reactor.new(port: 0, data_dir: $lab_dir, certificate: cert, key: key, logger: Logger.new(StringIO.new))
$lab_thread = Thread.new { $lab_server.run }
ENV["BURROW_CONNECT"] = "tls://127.0.0.1:#{$lab_server.port}"
ENV["BURROW_FINGERPRINT"] = $lab_server.fingerprint
require_relative "../lib/burrow/client/app"

Scarpe::Native.after_first_heartbeat do
  begin
    auto = Scarpe::Native::DisplayService.instance.automation
    client = Shoes.APPS.first.instance_variable_get(:@burrow)
    wait = lambda do |seconds = 20, &condition|
      deadline = Burrow.clock + seconds
      until condition.call
        if Burrow.clock > deadline
          st = client.state || {}
          host = $lab_server.rooms.values.first&.match
          raise "Lab timed out at #{caller_locations(1, 1).first}: client turn #{st['turn']} phase #{st['phase']} team #{st['team']} " \
            "mine #{client.my_turn?} rev #{client.scene&.terrain_revision}/#{st['terrain_revision']}; host turn #{host&.turn} phase #{host&.phase} winner #{host&.winner.inspect}"
        end
        auto.advance(0.03)
      end
    end
    auto.resize(1280, 800)
    wait.call { client.connection&.status == "online" }
    client.action("create", name: "Weapon lab", bots: 1, config: {"worms" => 2, "scheme" => "sandbox", "mines" => 0, "barrels" => 0,
      "crates" => false, "retreat_seconds" => 3, "turn_seconds" => 90, "wind" => 0.0})
    wait.call { client.room && client.room["members"].size == 2 }
    client.action("start")
    wait.call { client.page == :match && client.scene && client.scene.terrain_revision >= 0 }
    match = -> { $lab_server.rooms.values.first.match }
    world_point = lambda do |x, y|
      sx, sy = client.scene.camera.screen(x, y)
      scale = client.instance_variable_get(:@scale)
      [client.instance_variable_get(:@offset_x) + sx * scale, client.instance_variable_get(:@offset_y) + (sy + Burrow::Client::Scene::Y) * scale]
    end
    weapons = ENV["BURROW_LAB_WEAPONS"].to_s.split.then { |list| list.empty? ? Burrow::Catalog::WEAPONS.keys : list }
    weapons.each do |id|
      script = SCRIPTS.fetch(id)
      place = script.find { |step| step[0] == :place }
      setup = script.find { |step| step[0] == :setup }
      # Every reset installs a fresh course, so the terrain revision marks it.
      before = match.call.terrain.revision
      $lab_reset = {at: place && place[1]}.merge(setup ? setup[1] : {})
      wait.call do
        revision = client.state["terrain_revision"]
        revision > before && client.scene.terrain_revision == revision && client.my_turn? && client.state["phase"] == "aiming"
      end
      auto.advance(0.4)
      client.equip_weapon(id) or raise "#{id} could not be equipped"
      client.scene.camera.follow
      # Let follow finish framing the reset course before converting the first
      # world-space aim into native pointer coordinates.
      auto.advance(0.6)
      initial = match.call
      start_tick, start_turn, start_team = initial.tick, initial.turn, initial.team[:id]
      start_ammo = initial.team[:inventory].fetch(id)
      # Events survive course resets. Use IDs, not a tail of the shared ring, to
      # attribute accepted fire/activation and effects to this weapon alone.
      event_floor = initial.events.last&.fetch(:id) || 0
      event_cursor, lost_events, weapon_events = event_floor, 0, []
      script_action = {type: "ready"}
      folder = File.join(OUT, id)
      FileUtils.rm_rf(folder)
      FileUtils.mkdir_p(folder)
      frames, log = 0, []
      capture = lambda do
        m = match.call
        a = m.active
        fresh_events = m.events.select { |event| event[:id] > event_cursor }.map(&:dup)
        if fresh_events.any?
          lost_events += [fresh_events.first[:id] - event_cursor - 1, 0].max
          event_cursor = fresh_events.last[:id]
          weapon_events.concat(fresh_events)
        end
        log << {t: frames, tick: m.tick, turn: m.turn, phase: m.phase, team: m.team[:id], script_action: script_action,
          ammo: m.teams.find { |team| team[:id] == start_team }[:inventory].fetch(id),
          angle: client.instance_variable_get(:@angle), terrain_revision: m.terrain.revision, wind: m.wind,
          shots_left: m.instance_variable_get(:@shots_left), tool: m.instance_variable_get(:@tool)&.dup,
          effects: {double_damage: m.instance_variable_get(:@damage_boost), low_gravity: m.instance_variable_get(:@low_gravity)},
          active: a && a.slice(:id, :team, :x, :y, :vx, :vy, :hp, :rope, :jetpack, :fuel, :parachute, :launched, :poisoned, :shield, :frozen),
          enemies: m.worms.reject { |w| w[:team] == start_team }.map { |w| w.slice(:id, :x, :y, :vx, :vy, :hp, :launched, :poisoned) },
          projectiles: m.projectiles.map { |p| p.slice(:id, :weapon, :kind, :stage, :x, :y, :vx, :vy, :age, :delay, :life,
            :fragment, :stuck, :bounce, :sticky, :homing, :target_x, :target_y, :cruise, :choir_at, :remote, :drop_mine, :fire) },
          hazards: m.hazards.map { |h| h.slice(:id, :kind, :x, :y, :vx, :vy, :life, :armed, :trigger, :radius, :launched, :owner, :shots, :hp) },
          flame_count: m.hazards.count { |h| h[:kind] == "flame" },
          pending_salvos: m.instance_variable_get(:@salvos).to_a.size,
          events: fresh_events, notice: client.instance_variable_get(:@last_notice)}
        auto.snapshot(File.join(folder, format("frame-%02d.png", frames)))
        frames += 1
      end
      # Advance while capturing every `every` seconds.
      run = lambda do |seconds, every: 0.25|
        finish = Burrow.clock + seconds
        while Burrow.clock < finish
          step = [every, finish - Burrow.clock].min
          auto.advance(step)
          capture.call
        end
      end
      # A player scrolls or zooms out to see a distant target before clicking it.
      reveal = lambda do |point|
        sx, sy = client.scene.camera.screen(*point)
        next if sx.between?(60, 1380) && sy.between?(60, 640)
        me = match.call.active
        client.scene.camera.navigate((point[0] + me[:x]) / 2.0, (point[1] + me[:y]) / 2.0)
        auto.advance(0.5)
      end
      capture.call
      script.each do |action, arg, extra|
        script_action = {type: action, argument: arg, duration: extra}.compact
        case action
        when :place, :setup then nil
        when :aim
          reveal.call(arg)
          x, y = world_point.call(*arg)
          # A reset may leave the native cursor at this exact screen point.
          # Move first so a real motion event re-aims the new turn's grub.
          auto.mouse(:move, x - 2, y - 2)
          auto.advance(0.03)
          x, y = world_point.call(*arg)
          auto.mouse(:move, x, y)
          auto.advance(0.1)
        when :click
          reveal.call(arg)
          x, y = world_point.call(*arg)
          auto.mouse(:move, x, y)
          auto.mouse(:down, x, y)
          auto.mouse(:up, x, y)
          auto.advance(0.15)
          capture.call
        when :charge
          auto.key_down(" ")
          run.call(arg, every: 0.2)
          auto.key_up(" ")
          auto.advance(0.05)
        when :press
          wait.call(5) { !client.instance_variable_get(:@pending_action) }
          auto.key(arg)
          auto.advance(0.1)
          capture.call
        when :hold
          auto.key_down(arg)
          run.call(extra, every: 0.2)
          auto.key_up(arg)
        when :wait then run.call(arg)
        end
      end
      script_action = {type: "complete"}
      capture.call
      File.write(File.join(folder, "log.json"), JSON.pretty_generate(log))
      final = match.call
      fired = weapon_events.find { |event| event[:kind] == "fire" && event[:weapon] == id }
      handed_over = fired && weapon_events.any? { |event| event[:kind] == "turn" && event[:id] > fired[:id] }
      pending_hazards = final.hazards.count do |hazard|
        hazard[:kind] == "flame" || hazard[:trigger] ||
          (!hazard[:chute] && (hazard.fetch(:vx, 0).abs > 4 || hazard.fetch(:vy, 0).abs > 4))
      end
      moving_worms = final.worms.count { |worm| worm[:hp] > 0 && (worm[:vx].abs > 4 || worm[:vy].abs > 4) }
      clean = final.projectiles.empty? && final.instance_variable_get(:@salvos).to_a.empty? &&
        !final.instance_variable_get(:@tool) && pending_hazards.zero? && moving_worms.zero?
      summary[id] = {evidence_version: 2, frames: frames, notice: client.instance_variable_get(:@last_notice),
        start_tick: start_tick, final_tick: final.tick, start_turn: start_turn, final_turn: final.turn, phase: final.phase,
        start_ammo: start_ammo, final_ammo: final.teams.find { |team| team[:id] == start_team }[:inventory].fetch(id),
        event_floor: event_floor, lost_events: lost_events, fire_event_id: fired && fired[:id],
        turn_completed: !!(handed_over && final.turn > start_turn && final.phase == "aiming" && clean),
        remaining_projectiles: final.projectiles.size, pending_hazards: pending_hazards, moving_worms: moving_worms,
        peak_flames: log.map { |frame| frame[:flame_count] }.max,
        events: weapon_events, recent_events: weapon_events.last(12).map { |event| event[:kind] }}
      client.instance_variable_set(:@last_notice, nil)
      puts "#{id}: #{frames} frames, turn #{start_turn}→#{final.turn}, completed #{summary[id][:turn_completed]}, " \
        "events #{weapon_events.map { |event| event[:kind] }.uniq.join(',')}"
      $stdout.flush
      # Preserve completed weapons even if a later native input journey fails.
      File.write(File.join(OUT, "lab.json"), JSON.pretty_generate(summary))
    end
    File.write(File.join(OUT, "lab.json"), JSON.pretty_generate(summary))
  rescue Exception => error
    failed = true
    warn error.full_message
  ensure
    $lab_server.stop
    $lab_thread.join(5)
    Shoes.APPS.each(&:destroy)
  end
end
load File.join(Burrow::ROOT, "game.rb")
