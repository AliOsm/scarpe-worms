# frozen_string_literal: true

module Burrow
  module Client
    module MatchUI
      def cancel_controls(stop: true)
        if stop && my_turn?
          action("steer", direction: 0, lift: 0) if remote_critter&.fetch("stage", nil) == "flying" || state["tool"]
        end
        if stop && my_turn? && active_worm["hp"] > 0 && %w[aiming retreat].include?(state["phase"])
          action("move", direction: 0, lift: 0)
        end
        @keys.clear
        @camera_drag = nil
        @minimap_drag = nil
        @charge_started = @charge_source = nil
        @mouse_charge = false
        @last_input = nil
        @last_steer = nil
        @prediction&.clear_inputs
      end

      def draw_match(presentation: nil)
        @keys.clear
        @camera_drag = @minimap_drag = nil
        @scene = Scene.new(@shoes, self, scale: @scale, presentation: presentation)
        @scene.accept(state)
        box(0, 0, 1440, 104, color: shade("#0d2a5c", "#061430"), radius: 0)
        box(0, 99, 1440, 3, color: Theme::WELL_EDGE, radius: 0)
        box(0, 102, 1440, 2, color: Theme::INK, radius: 0)
        @team_hud = {}
        count = state["teams"].length
        column = 1184.0 / count
        state["teams"].each_with_index do |team, i|
          x = 18 + i * column
          width = column - 14
          color = COLORS[team["color"]]
          marker = box(x - 5, 5, width + 10, 60, color: "#ffd33522", radius: 30, stroke: Theme::YELLOW, stroke_width: 3)
          box(x, 10, width, 50, color: shade(Theme::DEEP, Theme::NAVY), radius: 25, stroke: "#4f8fe0", stroke_width: 2)
          box(x + 7, 16, 38, 38, color: color, radius: 11)
          image("grubs/#{team['color']}-idle-0", x + 2, 11, 48, 48)
          # Narrow capsules drop the grub counter so the team name keeps its room.
          roomy = count <= 3
          title_width = width - 54 - (roomy ? 116 : 56)
          title = label(short_text(team["name"], [(title_width / 8.2).floor, 6].max), x + 54, 13, title_width, size: roomy ? 15 : 14,
            color: color, font: Theme.display, weight: 700)
          members = label("", x + width - 112, 16, 50, size: 11, color: Theme::MUTED, font: Theme.display, align: "right") if roomy
          health = label("", x + width - 56, 13, 44, size: 15, color: Theme::WHITE, font: Theme.display, weight: 700, align: "right")
          bar_width = width - 68
          box(x + 52, 36, width - 64, 16, color: "#04101f", radius: 8)
          bar = box(x + 54, 38, bar_width, 12, color: color, radius: 6)
          @team_hud[team["id"]] = {bar: bar, width: bar_width, marker: marker, title: title, health: health, members: members}
        end
        @turn_label = label("", 22, 68, 760, size: 19, color: Theme::WHITE, font: Theme.display, weight: 700)
        @round_label = label("", 880, 74, 330, size: 12, color: Theme::MUTED, font: Theme.display, weight: 600, align: "right")
        button("Menu", 1224, 14, 196, height: 40, size: 18) { show_match_menu }
        box(0, 824, 1440, 76, color: shade("#061430", "#0d2a5c"), radius: 0)
        box(0, 822, 1440, 2, color: Theme::INK, radius: 0)
        box(0, 824, 1440, 3, color: Theme::WELL_EDGE, radius: 0)
        hud_box(12, 832, 192, 62)
        outlined("Wind", 24, 834, 80, size: 15, color: Theme::YELLOW, thickness: 1.5, offsets: Theme::OUTLINE.first(4))
        @wind_label = label("", 96, 835, 96, size: 12, color: Theme::WHITE, font: Theme.display, weight: 700, align: "right")
        box(22, 856, 172, 30, color: Theme::DEEP, radius: 15, stroke: Theme::INK, stroke_width: 2)
        box(107, 860, 2, 22, color: "#ffffff40", radius: 0)
        @wind_chevrons = {1 => [], -1 => []}
        3.times do |i|
          @wind_chevrons[1] << chevron(122 + i * 24, 871, 1)
          @wind_chevrons[-1] << chevron(94 - i * 24, 871, -1)
        end
        hud_box(1236, 832, 192, 62)
        @phase_label = label("TURN", 1248, 836, 90, size: 12, color: Theme::YELLOW, font: Theme.display, weight: 700)
        box(1300, 838, 118, 50, color: Theme::DEEP, radius: 16, stroke: Theme::INK, stroke_width: 2)
        @clock_label = label("45", 1300, 840, 118, size: 34, color: Theme::WHITE, font: Theme.display, weight: 700, align: "center")
        well(216, 832, 1010, 62, radius: 26)
        @shoes.oval(px(224), px(836), px(54), px(54), fill: shade("#09203f", "#123a6e"), stroke: "#06142b", strokewidth: px(2))
        @weapon_image = image("weapons/#{@selected_weapon}", 229, 841, 44, 44)
        @weapon_label = label("Pocket rocket", 288, 838, 160, size: 17, font: Theme.display, weight: 700, color: Theme::WHITE)
        @weapon_ammo = label("", 289, 865, 160, size: 12, color: Theme::MUTED)
        button("Arsenal · E", 452, 843, 120, height: 38, size: 15) { show_arsenal }
        @aim_label = label("", 586, 838, 172, size: 13, color: "#e3f1ff")
        box(584, 864, 172, 16, color: "#04101f", radius: 8, stroke: Theme::INK, stroke_width: 1)
        @power_bar = box(586, 866, 110, 12, color: shade(Theme::YELLOW, Theme::ORANGE), radius: 6)
        @power_minus = button("−", 766, 845, 34, height: 34, size: 18) { @power = [@power - 0.05, 0.05].max; refresh_match_hud }
        @power_plus = button("+", 808, 845, 34, height: 34, size: 18) { @power = [@power + 0.05, 1.0].min; refresh_match_hud }
        @fuse_button = button("Fuse #{@fuse}s", 852, 845, 100, height: 34, size: 14, tone: :navy) { @fuse = @fuse % 5 + 1; refresh_match_hud }
        @fire_button = button("Fire", 962, 840, 162, height: 44, primary: true, size: 17) { fire_current }
        @pass_button = button("Pass", 1136, 845, 80, height: 34, size: 15) { submit_weapon("fire", weapon: "skip") if my_turn? && state["phase"] == "aiming" && state["shots_left"].zero? }
        box(16, 788, 1050, 30, color: "#071731d9", radius: 15, stroke: "#3d7fd0aa")
        @control_hint = label("", 34, 795, 1020, size: 13, color: "#e3f1ff")
        @connection_overlay = @shoes.stack(left: 0, top: px(110), width: px(1440), height: px(46)) do
          box(360, 2, 720, 40, color: "#071731f0", radius: 20, stroke: Theme::YELLOW, stroke_width: 2)
          @reconnect_label = label("Rejoining your room…", 378, 12, 684, size: 14, color: Theme::WHITE, align: "center", font: Theme.display, weight: 600)
        end
        @connection_overlay.hide
        refresh_match_hud
      end

      # A small glossy plate for the corner gauges.
      def hud_box(x, y, width, height)
        box(x - 3, y - 3, width + 6, height + 6, color: Theme::INK, radius: 19)
        box(x, y, width, height, color: shade(*Theme::BLUE), radius: 16)
        box(x + 8, y + 2, width - 16, 18, color: shade("#ffffff4d", "#ffffff00"), radius: 12)
      end

      def chevron(x, y, direction)
        tip, back = x + 9 * direction, x - 9 * direction
        @shoes.shape(fill: Theme::WHITE, stroke: Theme::INK, strokewidth: px(1)) do
          @shoes.move_to(px(back), px(y - 10))
          @shoes.line_to(px(tip), px(y))
          @shoes.line_to(px(back), px(y + 10))
          @shoes.line_to(px(back + 6 * direction), px(y))
          @shoes.line_to(px(back), px(y - 10))
        end
      end

      def refresh_match_hud
        return unless @page == :match && state && @turn_label
        if @connection_status == "online"
          show_if(@connection_overlay, false)
        else
          show_if(@connection_overlay, true)
          set_text(@reconnect_label, @status_message)
        end
        active = active_worm
        title = if state["phase"] == "finished"
          "A well-earned breather"
        elsif my_turn?
          state["phase"] == "aiming" ? "Your turn, #{active['name']}  ·  Make trouble" : state["phase"] == "retreat" ? "Retreat, #{active['name']}!  ·  Get clear of the blast" : "Let's see where that lands…"
        else
          team = state["teams"].find { |t| t["id"] == state["team"] }
          "#{team['name']}  ·  #{active['name']}'s turn"
        end
        set_text(@turn_label, title)
        phase = state["phase"]
        seconds = phase == "retreat" ? state.fetch("retreat_seconds", 0) : state["seconds"]
        counting = %w[aiming retreat].include?(phase)
        remaining = seconds.ceil
        set_text(@clock_label, counting ? remaining.to_s.rjust(2, "0") : "··")
        set_text(@phase_label, {"aiming" => "TURN", "retreat" => "RETREAT", "settling" => "ACTION", "finished" => "FINISH"}.fetch(phase, "ACTION"))
        restyle(@clock_label, stroke: counting && (remaining <= 10 || phase == "retreat") ? "#ff5a45" : Theme::WHITE)
        cue = [state["turn"], phase, remaining]
        if @timer_cue != cue
          if counting && my_turn? && @window_active && remaining.between?(1, 5)
            @audio&.play("tick", volume: 0.35)
            if remaining == 5 && phase == "aiming"
              mine = state["teams"].find { |team| team["id"] == my_id }
              @audio&.voice_line("hurry-up", mine["color"]) if mine
            end
          end
          @timer_cue = cue
        end
        wind = state["wind"]
        arrow = wind >= 0 ? "→" : "←"
        set_text(@wind_label, wind.abs < 0.03 ? "Calm" : "#{arrow} #{(wind.abs * 10).round}")
        strength = wind.abs < 0.03 ? 0 : (wind.abs.clamp(0, 2) * 1.5).ceil.clamp(1, 3)
        @wind_chevrons.each do |direction, chevrons|
          chevrons.each_with_index do |chevron, i|
            shown = wind * direction > 0 && i < strength
            show_if(chevron, shown)
          end
        end
        set_text(@round_label, "ROUND #{state['round']}  ·  #{@rtt} ms")
        state["teams"].each do |team|
          members = state["worms"].select { |w| w["team"] == team["id"] }
          ratio = members.sum { |w| w["hp"] }.fdiv(members.sum { |w| w["max_hp"] })
          set_text(@team_hud[team["id"]][:health], members.sum { |w| w["hp"] }.to_s)
          set_text(@team_hud[team["id"]][:members], "#{members.count { |w| w['hp'] > 0 }} / #{members.length} grubs")
          restyle(@team_hud[team["id"]][:bar], width: px([@team_hud[team["id"]][:width] * ratio, 0.5].max))
          marker = @team_hud[team["id"]][:marker]
          show_if(marker, team["id"] == state["team"])
        end
        weapon = Catalog.fetch(@selected_weapon)
        path = File.join(Theme::ART, "weapons/#{@selected_weapon}.png")
        @weapon_image.path = path if @weapon_image.path != path
        set_text(@weapon_label, weapon[:name])
        ammo = (my_inventory || {}).fetch(@selected_weapon, 0)
        set_text(@weapon_ammo, "#{weapon[:group]} · #{ammo < 0 ? 'Unlimited' : "#{ammo} remaining"}")
        control = special_control
        critter = deployed_critter if my_turn?
        charged = Catalog.charged?(@selected_weapon) && !control
        aiming = my_turn? && state["phase"] == "aiming" && active["hp"] > 0
        detail = if active["jetpack"]
          "Fuel #{(active['fuel'].to_f / TICK_RATE).round(1)}s · W/↑ thrust"
        elsif active["rope"]
          rope = active["rope"]
          stage = rope["stage"] || "attached"
          stage == "shooting" ? "Hook flying…" : stage == "retracting" ? "Miss · retracting" : "Line #{rope['length'].to_f.round}px · W/S reels"
        elsif active["parachute"]
          active["parachute_open"] ? "Canopy open · A/D steers" : "Canopy armed · auto opens"
        elsif critter
          remaining = critter["stage"] == "flying" ? critter.fetch("flight_ticks", critter["life"]) : critter["life"]
          "#{critter['stage'].capitalize} · #{remaining.fdiv(TICK_RATE).ceil}s"
        elsif control
          tool_detail
        elsif @selected_weapon == "homing" && !@locked_target
          "Step 1 of 2 · pick a target"
        elsif @selected_weapon == "shotgun"
          state["shots_left"] > 0 ? "Shot 2 of 2 · re-aim, then tap" : "Shot 1 of 2 · aim, then tap"
        elsif @selected_weapon == "wind_control"
          "Keeps your turn · wind #{wind.abs < 0.03 ? 'calm' : "#{arrow} #{(wind.abs * 10).round}"}"
        elsif %w[shield double_damage low_gravity].include?(@selected_weapon)
          "Keeps your turn · #{supply_active? ? 'active' : 'ready'}"
        elsif %w[heal freeze skip].include?(@selected_weapon)
          "Uses your turn · tap to use"
        elsif %w[mine turret barrel].include?(@selected_weapon)
          "Place ahead · then retreat"
        elsif charged
          "Aim #{@angle.abs.round}° · Power #{(@power * 100).round}%"
        elsif weapon[:kind] == "girder"
          "Tilt #{girder_rotation.round}° · ← → turns"
        elsif Catalog::SKY.include?(weapon[:kind]) && weapon[:kind] != "meteor"
          "Approach from the #{strike_direction.negative? ? 'right ←' : 'left →'}"
        else
          Catalog::AIMED.include?(weapon[:kind]) ? "Aim #{@angle.abs.round}° · tap to fire" : "Ready to deploy"
        end
        set_text(@aim_label, detail)
        restyle(@power_bar, width: px(168 * (charged ? @power : active["jetpack"] ? active["fuel"].fdiv(5 * TICK_RATE).clamp(0, 1) : 0)))
        @power_minus.state = @power_plus.state = aiming && charged ? nil : "disabled"
        set_text(@fuse_button, @selected_weapon == "holy_bomb" ? "5s + rest" : @selected_weapon == "dynamite" ? "Fixed 4s" : Catalog::FUSED.include?(@selected_weapon) ? "Fuse #{@fuse}s" : "No fuse")
        @fuse_button.state = aiming && Catalog::FUSED.include?(@selected_weapon) && !control ? nil : "disabled"
        set_text(@fire_button, @pending_action ? "Sending…" : control ? control[0] : critter ? (critter["kind"] == "herd" ? "Stampeding…" : "#{critter['stage'].capitalize}…") : @charge_started ? "Charging…" : state["shots_left"] > 0 ? "Shot 2 · Space" : @selected_weapon == "homing" && !@locked_target ? "1 · Lock target" : @selected_weapon == "homing" ? "2 · Launch" : weapon_fire_label)
        @fire_button.state = my_turn? && !@pending_action && (control || (aiming && can_equip?(@selected_weapon))) ? nil : "disabled"
        @pass_button.state = aiming && state["shots_left"].zero? && !@pending_action ? nil : "disabled"
        hint = if !my_turn?
          "Watching the action · G map · F follow · pinch zoom · two-finger pan · E browse arsenal"
        elsif control
          control[1]
        elsif critter
          case critter["kind"]
          when "poisoner" then "Stink express is spraying as it runs · finishes with gas and a small blast"
          when "herd" then "Cattle call · three runners explode on walls or grubs · F follows the herd"
          else "Captain wool is falling · collision or timeout ends the flight"
          end
        elsif state["phase"] == "retreat"
          "Retreat! A / D moves · W jumps · B backflips · watch where the shot lands"
        elsif state["phase"] != "aiming"
          "Waiting for the action to settle · G map · F follow"
        elsif @selected_weapon == "shotgun" && state["shots_left"] > 0
          "One shot left in this cartridge · move and re-aim · Space or click fires shot two"
        elsif supply_active?
          "#{weapon[:name]} is active · your turn continues · E opens the arsenal for your next action"
        elsif @selected_weapon == "homing"
          @locked_target ? "Step 2 of 2 · Aim with the mouse or ↑ ↓ · hold the mouse or Space, release to launch · Backspace re-targets" :
            "Step 1 of 2 · Click the target to lock it (Space locks at the pointer)"
        else
          Catalog.hint(@selected_weapon)
        end
        set_text(@control_hint, hint)
      end

      def remote_critter
        state && state["projectiles"].find { |p| p["owner"] == my_id && p["remote"] && p["life"] > 0 }
      end

      def deployed_critter
        state && state["projectiles"].find { |p| p["owner"] == my_id && %w[walker guided digger poisoner herd].include?(p["kind"]) && p["life"] > 0 }
      end

      def supply_active?
        case @selected_weapon
        when "shield" then active_worm && active_worm["shield"]
        when "double_damage" then state.dig("effects", "double_damage")
        when "low_gravity" then state.dig("effects", "low_gravity")
        end
      end

      def tool_detail
        tool = state["tool"]
        return "Tool active" unless tool
        name = {"drill" => "Drilling", "torch" => "Cutting", "dash" => "Dashing"}.fetch(tool["kind"], "Tool active")
        "#{name} · #{([tool.fetch('until', state['tick']) - state['tick'], 0].max.fdiv(TICK_RATE)).round(1)}s"
      end

      def weapon_fire_label
        return "Call strike" if %w[airstrike mine_strike napalm].include?(@selected_weapon)
        return "Call meteors" if @selected_weapon == "meteor"
        action = case @selected_weapon
        when "shotgun" then "Shot 1"
        when "fire_punch" then "Punch"
        when "dragon_punch" then "Dash"
        when "prod" then "Poke"
        when "bat" then "Swing"
        when "axe" then "Chop"
        when "dynamite", "mine", "turret", "barrel" then "Place"
        when "earthquake" then "Shake"
        when "drill" then "Drill"
        when "blowtorch" then "Cut"
        when "heal" then "Heal"
        when "shield" then "Shield"
        when "freeze" then "Freeze"
        when "double_damage" then "Boost"
        when "low_gravity" then "Float"
        when "wind_control" then "Wind"
        when "skip" then "Pass"
        else Catalog.fetch(@selected_weapon)[:group] == "Critters" ? "Release" : "Fire"
        end
        "#{action} · Space"
      end

      def special_control
        if (p = remote_critter)
          case [p["kind"], p["stage"]]
          when ["guided", "walking"] then ["Launch · Space", "Captain wool is running · tap Space to take flight"]
          when ["guided", "flying"] then ["Detonate · Space", "← / → or A / D steers Captain wool · Space or click explodes · after 8s it falls"]
          when ["guided", "falling"] then ["Detonate · Space", "Captain wool's flight is over · Space or click explodes before impact"]
          when ["digger", "walking"] then ["Dive · Space", "Tunnel buddy is running · Space starts the dive"]
          when ["digger", "diving"], ["digger", "digging"] then ["Detonate · Space", "Tunnel buddy digs through the ground · Space or click explodes · grubs and tunnel exits detonate"]
          when ["poisoner", "walking"] then ["Spray · Space", "Stink express is running · Space releases the poison"]
          when ["cluster", "thrown"] then ["Split · Space", "Fruit salad is in the air · Space splits it now"]
          else ["Detonate · Space", "Tap Space or click to detonate the critter"]
          end
        elsif state && state["tool"]
          hint = case state["tool"]["kind"]
          when "torch" then "↑ / ↓ changes tunnel slope · Space or click stops cutting early"
          when "dash" then "Dragon dash carves forward · Space or click stops the rush"
          else "Drilling downward · Space or click stops drilling early"
          end
          ["Stop · Space", hint]
        elsif @selected_weapon == "rope" && active_worm && active_worm["rope"]
          rope = active_worm["rope"]
          if rope && %w[shooting retracting].include?(rope["stage"])
            ["Cancel · Space", "Hook flying · Space or Enter recalls · a miss costs no ammo"]
          else
            ["Detach · Space", "A/D or ←/→ swings · W/S or ↑/↓ reels · Space/Enter releases · fire again before landing"]
          end
        elsif @selected_weapon == "jetpack" && active_worm && active_worm["jetpack"]
          ["Land · Space", "W/↑ thrust · A/D or ←/→ flies sideways · S/↓ descends · release keys saves fuel · Space parachutes"]
        end
      end

      def strike_direction = @strike_direction || 1
      def girder_rotation = @girder_rotation || 0.0

      # Arrow keys steer an air strike's approach or tilt a girder; A / D still walk.
      def arrow_targeting?
        return false unless state && my_turn? && state["phase"] == "aiming" && !special_control
        kind = Catalog.fetch(@selected_weapon)[:kind]
        kind == "girder" || (Catalog::SKY.include?(kind) && kind != "meteor")
      end

      def adjust_targeting(step)
        return unless arrow_targeting?
        if Catalog.fetch(@selected_weapon)[:kind] == "girder"
          @girder_rotation = (girder_rotation + step * 22.5).clamp(-90.0, 90.0)
        else
          @strike_direction = step
        end
        @audio&.play("click", volume: 0.4)
        refresh_match_hud
      end

      def retarget
        return unless @locked_target && !@charge_started
        @locked_target = nil
        notify("Target cleared. Click a new destination.")
        refresh_match_hud
      end

      def equip_weapon(id)
        return false unless can_equip?(id)
        cancel_controls
        @locked_target = nil
        @selected_weapon = id
        @audio&.play("equip", volume: 0.5)
        true
      end

      def can_equip?(id)
        return false unless my_turn? && state["phase"] == "aiming" && !@pending_action
        return false if state["shots_left"] > 0 && id != "shotgun"
        return false if state.dig("config", "terrain") == "cavern" && Catalog::SKY.include?(Catalog.fetch(id)[:kind])
        (my_inventory || {}).fetch(id, 0) != 0 || (id == "shotgun" && state["shots_left"] > 0) || (id == "rope" && active_worm["rope_use"])
      end

      def normalize_key(key)
        value = key.to_s.downcase
        return "enter" if ["\n", "\r", "return"].include?(value)
        value == "space" ? " " : value
      end

      def key_down(key)
        key = normalize_key(key)
        if key == "escape"
          overlay? ? hide_overlay : (@page == :match ? show_match_menu : to_menu)
          return
        end
        return arsenal_key(key) if @arsenal && @window_active
        return if overlay? || @page != :match || !@window_active
        return if @keys.include?(key)
        @keys << key
        case key
        when "g", "tab", "\t" then scene.toggle_map
        when "f" then scene.camera.follow
        when "=", "+", "r" then scene.camera.zoom_by(1)
        when "-", "q" then scene.camera.zoom_by(-1)
        when "e" then show_arsenal
        when "h" then show_guide
        when "t" then show_chat
        when "m"
          preferences["muted"] = !preferences["muted"]
          @audio.refresh
          notify(preferences["muted"] ? "Sound muted" : "Sound on")
        when "1", "2", "3", "4", "5"
          @fuse = key.to_i
        when "left", "right"
          adjust_targeting(key == "right" ? 1 : -1)
        when "backspace", "delete"
          retarget
        when "w", "enter", "b"
          # W/S become thrust and reel controls while mobility tools own the grub.
          # Outside those tools W remains the familiar jump key.
          mobility = active_worm && (active_worm["jetpack"] || active_worm["rope"])
          if !(key == "w" && mobility) && my_turn? && active_worm["hp"] > 0 && !(remote_critter && remote_critter["kind"] != "cluster") && !state["tool"] && %w[aiming retreat].include?(state["phase"])
            # Detachment changes the Fire stage, so Jump releases use the same
            # snapshot acknowledgement gate as a Space release.
            active_worm["rope"] ? submit_weapon("jump", backflip: key == "b") : action("jump", backflip: key == "b")
          end
        when " " then begin_fire(:keyboard)
        end
        update_controls(force: %w[left right a d].include?(key) && remote_critter&.fetch("stage", nil) == "flying") if %w[left right a d up down w s].include?(key)
      end

      def key_up(key)
        key = normalize_key(key)
        @keys.delete(key)
        release_charge(source: :keyboard) if key == " " && @charge_started
        update_controls(force: %w[left right a d].include?(key) && remote_critter&.fetch("stage", nil) == "flying") if %w[left right a d up down w s].include?(key)
      end

      def pointer(x, y)
        return if @page != :match || overlay?
        wx, wy = (x - @offset_x) / @scale, (y - @offset_y) / @scale - Scene::Y
        if @camera_drag
          scene.camera.pan(@camera_drag[0] - wx, @camera_drag[1] - wy)
          @camera_drag = [wx, wy]
          return
        end
        if @minimap_drag
          scene.navigate(wx, wy)
          return
        end
        return unless wx.between?(0, 1440) && wy.between?(0, 720)
        return if scene.navigation_hit?(wx, wy)
        wx, wy = scene.camera.world(wx, wy)
        @target = [wx.round(2), wy.round(2)]
        if active_worm && my_turn? && !special_control
          # Aim from the grub the player can see, including predicted movement.
          shown = scene.presented if @prediction&.active? && scene.respond_to?(:presented)
          origin = shown && shown["worms"].find { |w| w["id"] == state["active"] }
          origin ||= active_worm
          @angle = Math.atan2(wy - origin["y"] + 13, wx - origin["x"]) * 180 / Math::PI
        end
      end

      def pointer_click(button, x, y)
        return if @page != :match || overlay? || !@window_active
        wx, wy = (x - @offset_x) / @scale, (y - @offset_y) / @scale - Scene::Y
        return unless wx.between?(0, 1440) && wy.between?(0, 720)
        if button == 2
          @camera_drag = [wx, wy]
          return
        end
        if button == 1 && scene.respond_to?(:minimap_hit?) && scene.minimap_hit?(wx, wy)
          @minimap_drag = true
          scene.navigate(wx, wy)
          return
        end
        if scene.navigation_hit?(wx, wy)
          scene.navigate(wx, wy) if button == 1
          return
        end
        if button == 3
          show_arsenal
          return
        end
        return unless button == 1 && my_turn?
        pointer(x, y)
        # Homing is two steps: the first click locks the destination, then the
        # mouse charges the launch like any other charged weapon.
        if @selected_weapon == "homing" && !special_control && state["phase"] == "aiming" && !@locked_target
          lock_homing_target
        else
          begin_fire(:mouse)
        end
      end

      def lock_homing_target
        return if @pending_action || @charge_started
        @locked_target = bounded_target
        @audio&.play("equip", volume: 0.5)
        notify("Target locked. Now aim, then hold the mouse or Space and release to launch.")
        refresh_match_hud
      end

      def begin_fire(source)
        return unless my_turn? && !@pending_action && !@charge_started && !overlay? && @window_active
        if special_control
          submit_weapon("activate")
        elsif state["phase"] == "aiming" && active_worm["hp"] > 0 && can_equip?(@selected_weapon)
          if @selected_weapon == "homing" && !@locked_target
            lock_homing_target
          elsif Catalog.charged?(@selected_weapon)
            @charge_started, @charge_source = Burrow.clock, source
            @charge_turn, @charge_weapon = state["turn"], @selected_weapon
            @mouse_charge = source == :mouse
            @power = 0.05
          else
            fire_current
          end
        end
      end

      def update_controls(force: false)
        return unless my_turn? && !overlay? && @window_active
        now = Burrow.clock
        if @charge_started
          if state["phase"] != "aiming" || state["turn"] != @charge_turn || @selected_weapon != @charge_weapon
            cancel_controls(stop: false)
          else
            @power = ((now - @charge_started) / 1.35 + 0.05).clamp(0.05, 1)
            release_charge if @power >= 1
          end
        end
        refresh = force || now - (@last_input_at || 0) > 0.08
        @last_input_at = now if refresh
        return if !refresh && respond_to?(:responsive_movement?) && !responsive_movement?
        arrows = !arrow_targeting?
        direction = (@keys.intersect?(arrows ? Set["d", "right"] : Set["d"]) ? 1 : 0) - (@keys.intersect?(arrows ? Set["a", "left"] : Set["a"]) ? 1 : 0)
        # Mobility tools accept both the arrow cluster and WASD. W is upward
        # thrust for the jetpack and reel-in for the rope; S is gentle down/reel-out.
        mobility = active_worm && (active_worm["jetpack"] || active_worm["rope"])
        lift = ((@keys.include?("up") || (mobility && @keys.include?("w"))) ? 1 : 0) -
          ((@keys.include?("down") || (mobility && @keys.include?("s"))) ? 1 : 0)
        # Critters take over the controls; a thrown fruit salad leaves the grub free to retreat.
        if (p = remote_critter) && p["kind"] != "cluster"
          if p["stage"] == "flying" && (refresh || @last_steer != [direction, 0])
            @last_steer = [direction, 0] if action("steer", direction: direction)
          end
          return
        elsif state["tool"]
          if state["tool"]["kind"] == "torch" && (refresh || @last_steer != [0, lift])
            @last_steer = [0, lift] if action("steer", lift: lift)
          end
          return
        end
        return unless active_worm && active_worm["hp"] > 0
        if active_worm["fuel"].to_i <= 0 && !active_worm["rope"]
          @angle = (@angle - lift * (active_worm["facing"] > 0 ? 2.0 : -2.0)).clamp(-180, 180) if refresh
          lift = 0
        end
        if direction != 0 && direction * Math.cos(@angle * Math::PI / 180) < 0
          @angle = @angle >= 0 ? 180 - @angle : -180 - @angle
        end
        input = [direction, lift]
        if %w[aiming retreat].include?(state["phase"]) && (input != @last_input || (refresh && (direction != 0 || lift != 0)))
          @last_input = input if action("move", direction: direction, lift: lift)
        end
      end

      def release_charge(source: nil)
        return unless @charge_started && (!source || source == @charge_source)
        valid = state && @charge_turn == state["turn"] && @charge_weapon == @selected_weapon
        @charge_started = @charge_source = nil
        @mouse_charge = false
        fire_current if valid && !overlay? && @window_active
      end

      def bounded_target
        [@target[0].clamp(0, state.fetch("world_width", WIDTH)), @target[1].clamp(0, state.fetch("world_height", HEIGHT))]
      end

      # The worker supplies the same collision mask used to paint the visible
      # landscape. Cache expensive placement geometry for each host snapshot.
      def placement_preview
        kind = Catalog.fetch(@selected_weapon)[:kind]
        return nil unless %w[teleport girder].include?(kind) && state
        terrain = scene.preview_terrain
        return {valid: nil, message: "Checking ground…"} unless terrain && terrain.revision == state["terrain_revision"]
        x, y = bounded_target
        key = [state["tick"], terrain.object_id, kind, x, y, girder_rotation]
        return @placement_preview if @placement_preview_key == key
        @placement_preview_key = key
        options = {water: state["water"], worms: state["worms"]}
        @placement_preview = if kind == "teleport"
          Placement.teleport(terrain, x, y, **options, active_id: state["active"])
        else
          Placement.girder(terrain, x, y, **options, rotation: girder_rotation)
        end
      end

      def submit_weapon(type, **values)
        return if @pending_action
        @pending_action = connection.sequence if action(type, **values)
        @charge_started = @charge_source = nil
        @mouse_charge = false
      end

      def fire_current
        return unless my_turn? && !overlay? && @window_active && !@pending_action
        if special_control
          submit_weapon("activate")
          return
        end
        return unless state["phase"] == "aiming" && active_worm["hp"] > 0 && can_equip?(@selected_weapon)
        if @selected_weapon == "homing" && !@locked_target
          lock_homing_target
          return
        end
        target = @selected_weapon == "homing" ? @locked_target : bounded_target
        submit_weapon("fire", weapon: @selected_weapon, angle: @angle.round(3), power: @power.round(3),
          fuse: @fuse, x: target[0], y: target[1], direction: strike_direction, rotation: girder_rotation)
      end
    end
  end
end
