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
        @charge_started = @charge_source = nil
        @mouse_charge = false
        @last_input = nil
      end

      def draw_match(presentation: nil)
        @keys.clear
        @scene = Scene.new(@shoes, self, scale: @scale, presentation: presentation)
        @scene.accept(state)
        box(0, 0, 1440, 104, color: Theme::INK, radius: 0)
        @team_hud = {}
        count = state["teams"].length
        column = 1320.0 / count
        state["teams"].each_with_index do |team, i|
          x = 32 + i * column
          marker = box(x - 9, 13, 3, 37, color: COLORS[team["color"]], radius: 1)
          title = label(team["name"], x, 14, column - 25, size: 15, color: COLORS[team["color"]], font: Theme.display)
          box(x, 45, column - 30, 6, color: "#ffffff20", radius: 3)
          bar = box(x, 45, column - 30, 6, color: COLORS[team["color"]], radius: 3)
          @team_hud[team["id"]] = {bar: bar, width: column - 30, marker: marker, title: title}
        end
        @turn_label = label("", 34, 70, 624, size: 15, color: Theme::WHITE, font: Theme.display)
        box(681, 59, 80, 39, color: "#ffffff12", radius: 9)
        @clock_label = label("45", 678, 60, 86, size: 27, color: Theme::GOLD, font: Theme.mono, align: "center")
        @wind_label = label("", 879, 74, 334, size: 12, color: "#b9d6d1", align: "right")
        button("Menu", 1298, 62, 108, height: 32) { show_match_menu }
        box(0, 824, 1440, 76, color: Theme::PAPER, radius: 0)
        line(0, 824, 1440, 824)
        @weapon_image = image("weapons/#{@selected_weapon}", 22, 835, 47, 47)
        @weapon_label = label("Pocket rocket", 84, 835, 230, size: 19, font: Theme.display)
        @weapon_ammo = label("", 86, 866, 220, size: 12, color: Theme::MUTED)
        button("Arsenal · E", 310, 845, 156) { show_arsenal }
        @aim_label = label("", 491, 837, 255, size: 13, color: Theme::MUTED)
        @power_bg = box(490, 870, 225, 7, color: "#d9d4c7", radius: 3)
        @power_bar = box(490, 870, 146, 7, color: Theme::ORANGE, radius: 3)
        @power_minus = button("−", 731, 845, 44, height: 32) { @power = [@power - 0.05, 0.05].max; refresh_match_hud }
        @power_plus = button("+", 784, 845, 44, height: 32) { @power = [@power + 0.05, 1.0].min; refresh_match_hud }
        @fuse_button = button("Fuse: #{@fuse}s", 850, 845, 140) { @fuse = @fuse % 5 + 1; refresh_match_hud }
        @fire_button = button("Fire", 1018, 843, 223, primary: true) { fire_current }
        @pass_button = button("Pass", 1264, 845, 142) { submit_weapon("fire", weapon: "skip") if my_turn? && state["phase"] == "aiming" && state["shots_left"].zero? }
        box(16, 790, 1050, 28, color: "#182d35e8", radius: 7)
        @control_hint = label("", 30, 797, 1020, size: 12, color: Theme::WHITE)
        @connection_overlay = @shoes.stack(left: 0, top: px(106), width: px(1440), height: px(42)) do
          box(360, 0, 720, 38, color: Theme::INK, radius: 9)
          @reconnect_label = label("Rejoining your room…", 378, 10, 684, size: 13, color: Theme::WHITE, align: "center")
        end
        @connection_overlay.hide
        refresh_match_hud
      end

      def refresh_match_hud
        return unless @page == :match && state && @turn_label
        if @connection_status == "online"
          @connection_overlay.hide
        else
          @connection_overlay.show
          set_text(@reconnect_label, @status_message)
        end
        active = active_worm
        title = if state["phase"] == "finished"
          "A well-earned breather"
        elsif my_turn?
          state["phase"] == "aiming" ? "Your turn, #{active['name']}  ·  Move, aim, make trouble" : state["phase"] == "retreat" ? "Make yourself scarce! Retreat while you can." : "Let's see where that lands…"
        else
          team = state["teams"].find { |t| t["id"] == state["team"] }
          "#{team['name']}  ·  #{active['name']}'s turn"
        end
        set_text(@turn_label, title)
        set_text(@clock_label, state["phase"] == "aiming" ? state["seconds"].ceil.to_s.rjust(2, "0") : "··")
        @clock_label.style(stroke: state["seconds"] < 10 ? "#ef765e" : Theme::GOLD)
        arrow = state["wind"] >= 0 ? "→" : "←"
        set_text(@wind_label, "ROUND #{state['round']}  ·  WIND #{arrow} #{(state['wind'].abs * 10).round}  ·  #{@rtt} ms")
        state["teams"].each do |team|
          members = state["worms"].select { |w| w["team"] == team["id"] }
          ratio = members.sum { |w| w["hp"] }.fdiv(members.sum { |w| w["max_hp"] })
          @team_hud[team["id"]][:bar].style(width: px([@team_hud[team["id"]][:width] * ratio, 0.5].max))
          marker = @team_hud[team["id"]][:marker]
          team["id"] == state["team"] ? marker.show : marker.hide
        end
        weapon = Catalog.fetch(@selected_weapon)
        @weapon_image.path = File.join(Theme::ART, "weapons/#{@selected_weapon}.png")
        set_text(@weapon_label, weapon[:name])
        ammo = (my_inventory || {}).fetch(@selected_weapon, 0)
        set_text(@weapon_ammo, "#{weapon[:group]} · #{ammo < 0 ? 'Unlimited' : "#{ammo} remaining"}")
        control = special_control
        charged = Catalog.charged?(@selected_weapon) && !control
        aiming = my_turn? && state["phase"] == "aiming" && active["hp"] > 0
        detail = if active["jetpack"]
          "Fuel #{(active['fuel'].fdiv(TICK_RATE)).round(1)}s · arrows fly"
        elsif active["rope"]
          "Line #{active['rope']['length'].round} · ↑↓ reel"
        elsif control
          remote_critter ? "#{remote_critter['stage'].capitalize} · #{(remote_critter['life'].fdiv(TICK_RATE)).ceil}s" : "Tool active"
        elsif charged
          "Aim #{@angle.abs.round}° · Power #{(@power * 100).round}%"
        else
          Catalog::AIMED.include?(weapon[:kind]) ? "Aim #{@angle.abs.round}° · tap to fire" : "Ready to deploy"
        end
        set_text(@aim_label, detail)
        @power_bar.style(width: px(225 * (charged ? @power : active["jetpack"] ? active["fuel"].fdiv(4 * TICK_RATE) : 0)))
        @power_minus.state = @power_plus.state = aiming && charged ? nil : "disabled"
        @fuse_button.text = @selected_weapon == "holy_bomb" ? "Fuse: 5s fixed" : Catalog::FUSED.include?(@selected_weapon) ? "Fuse: #{@fuse}s" : "No fuse"
        @fuse_button.state = aiming && Catalog::FUSED.include?(@selected_weapon) && !control ? nil : "disabled"
        @fire_button.text = @pending_action ? "Sending…" : control ? control[0] : @charge_started ? "Charging…" : state["shots_left"] > 0 ? "Second shot" : @selected_weapon == "homing" && !@locked_target ? "Lock target" : "Fire · Space"
        @fire_button.state = my_turn? && !@pending_action && (control || (aiming && can_equip?(@selected_weapon))) ? nil : "disabled"
        @pass_button.state = aiming && state["shots_left"].zero? && !@pending_action ? nil : "disabled"
        hint = if !my_turn?
          "Watching the action · G map · F follow · Q / R zoom · E browse arsenal"
        elsif control
          control[1]
        elsif state["phase"] == "retreat"
          "Retreat! A / D moves · W jumps · B backflips · watch where the shot lands"
        elsif state["phase"] != "aiming"
          "Waiting for the action to settle · G map · F follow"
        else
          Catalog.hint(@selected_weapon)
        end
        set_text(@control_hint, hint)
      end

      def remote_critter
        state && state["projectiles"].find { |p| p["owner"] == my_id && p["remote"] && p["life"] > 0 }
      end

      def special_control
        if (p = remote_critter)
          case [p["kind"], p["stage"]]
          when ["guided", "walking"] then ["Launch · Space", "Captain wool is running · tap Space to take flight"]
          when ["guided", "flying"] then ["Drop · Space", "Left / Right turns Captain wool · Space drops it onto the target"]
          when ["digger", "walking"] then ["Dive · Space", "Tunnel buddy is running · Space starts the dive"]
          when ["poisoner", "walking"] then ["Spray · Space", "Stink express is running · Space releases the poison"]
          else ["Detonate · Space", "Tap Space or click to detonate the critter"]
          end
        elsif state && state["tool"]
          ["Stop · Space", state["tool"]["kind"] == "torch" ? "Up / Down changes tunnel slope · Space stops digging" : "Space stops drilling early"]
        elsif @selected_weapon == "rope" && active_worm && active_worm["rope"]
          ["Detach · Space", "Left / Right swings · Up / Down reels · Space or Jump releases"]
        elsif @selected_weapon == "jetpack" && active_worm && active_worm["jetpack"]
          ["Land · Space", "Arrow keys fly · release keys to save fuel · Space deploys a parachute"]
        end
      end

      def equip_weapon(id)
        return false unless can_equip?(id)
        cancel_controls
        @locked_target = nil
        @selected_weapon = id
        true
      end

      def can_equip?(id)
        return false unless my_turn? && state["phase"] == "aiming" && !@pending_action
        return false if state["shots_left"] > 0 && id != "shotgun"
        return false if state.dig("config", "terrain") == "cavern" && Catalog::SKY.include?(Catalog.fetch(id)[:kind])
        (my_inventory || {}).fetch(id, 0) != 0 || (id == "shotgun" && state["shots_left"] > 0)
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
        when "w", "enter", "b"
          action("jump", backflip: key == "b") if my_turn? && active_worm["hp"] > 0 && !remote_critter && !state["tool"] && %w[aiming retreat].include?(state["phase"])
        when " " then begin_fire(:keyboard)
        end
      end

      def key_up(key)
        key = normalize_key(key)
        @keys.delete(key)
        release_charge(source: :keyboard) if key == " " && @charge_started
      end

      def pointer(x, y)
        return if @page != :match || overlay?
        wx, wy = (x - @offset_x) / @scale, (y - @offset_y) / @scale - Scene::Y
        if @camera_drag
          scene.camera.pan(@camera_drag[0] - wx, @camera_drag[1] - wy)
          @camera_drag = [wx, wy]
          return
        end
        return unless wx.between?(0, 1440) && wy.between?(0, 720)
        return if scene.navigation_hit?(wx, wy)
        wx, wy = scene.camera.world(wx, wy)
        @target = [wx.round(2), wy.round(2)]
        if active_worm && my_turn? && !special_control
          @angle = Math.atan2(wy - active_worm["y"] + 13, wx - active_worm["x"]) * 180 / Math::PI
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
        if @selected_weapon == "homing" && !special_control && state["phase"] == "aiming"
          lock_homing_target
        else
          begin_fire(:mouse)
        end
      end

      def lock_homing_target
        return if @pending_action || @charge_started
        @locked_target = bounded_target
        notify("Target locked. Aim the launch, then hold Space and release.")
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

      def update_controls
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
        return unless now - (@last_input_at || 0) > 0.08
        @last_input_at = now
        direction = (@keys.intersect?(Set["d", "right"]) ? 1 : 0) - (@keys.intersect?(Set["a", "left"]) ? 1 : 0)
        lift = (@keys.include?("up") ? 1 : 0) - (@keys.include?("down") ? 1 : 0)
        if (p = remote_critter)
          action("steer", direction: direction) if p["stage"] == "flying"
          return
        elsif state["tool"]
          action("steer", lift: lift) if state["tool"]["kind"] == "torch"
          return
        end
        return unless active_worm && active_worm["hp"] > 0
        if active_worm["fuel"].to_i <= 0 && !active_worm["rope"]
          @angle = (@angle - lift * (active_worm["facing"] > 0 ? 2.0 : -2.0)).clamp(-180, 180)
          lift = 0
        end
        if direction != 0 && direction * Math.cos(@angle * Math::PI / 180) < 0
          @angle = @angle >= 0 ? 180 - @angle : -180 - @angle
        end
        input = [direction, lift]
        if %w[aiming retreat].include?(state["phase"]) && (input != @last_input || direction != 0 || lift != 0)
          action("move", direction: direction, lift: lift)
          @last_input = input
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
          fuse: @fuse, x: target[0], y: target[1])
      end
    end
  end
end
