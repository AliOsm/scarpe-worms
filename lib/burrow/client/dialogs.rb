# frozen_string_literal: true

module Burrow
  module Client
    module Dialogs
      def overlay(title, subtitle = "", width: 1060, height: 700, &body)
        cancel_controls
        @audio&.play("open", volume: 0.4) unless @overlay
        @chat_log = @chat_content = @chat_signature = nil
        @overlay = title
        @content.style(inert: true)
        @modal.show
        @modal.clear do
          box(0, 0, 1440, 900, color: "#10252cb8", radius: 0)
          @dialog_x, @dialog_y = (1440 - width) / 2, (900 - height) / 2
          box(@dialog_x, @dialog_y + 7, width, height, color: "#071b2b66", radius: 18)
          box(@dialog_x, @dialog_y, width, height, color: Theme::PANEL, radius: 18)
          box(@dialog_x, @dialog_y, width, 106, color: Theme::INK, radius: 18)
          box(@dialog_x, @dialog_y + 74, width, 32, color: Theme::INK, radius: 0)
          box(@dialog_x + 30, @dialog_y + 103, 72, 3, color: Theme::ORANGE, radius: 1)
          label(title, @dialog_x + 30, @dialog_y + 22, width - 190, size: 31, font: Theme.display, color: Theme::WHITE)
          label(subtitle, @dialog_x + 32, @dialog_y + 72, width - 64, size: 14, color: "#b6cdcb") unless subtitle.empty?
          button("Close", @dialog_x + width - 116, @dialog_y + 27, 86, height: 32,
            color: Theme::SLATE, text_color: Theme::WHITE) { hide_overlay }
          body.call(@dialog_x, @dialog_y)
        end
        place_toast
      end

      def hide_overlay
        @audio&.play("close", volume: 0.35) if @overlay
        @overlay = nil
        @rules_draft = nil unless @switching_rules_tab
        @content&.style(inert: false)
        @modal&.clear
        @modal&.hide
        @keys.clear
        @mouse_charge = false
        @charge_started = nil
        @chat_log = @chat_content = @chat_signature = nil
        place_toast
      end

      def show_connect
        overlay("A little multiplayer mayhem", "Connect to a host, paste an invite, or host your own room.", width: 960, height: 600) do |x, y|
          label("Your name", x + 36, y + 126, 330, size: 14)
          name = input(preferences["name"], x + 36, y + 153, 350)
          label("Server address or invite", x + 36, y + 212, 740, size: 14)
          endpoint = input(preferences["endpoint"], x + 36, y + 240, 886)
          label("Certificate fingerprint (for a self-hosted server)", x + 36, y + 300, 850, size: 14)
          fingerprint = input(preferences["fingerprint"], x + 36, y + 328, 886)
          label("A burrow:// invite fills in the server, room, and fingerprint for you.", x + 36, y + 385, 880, size: 14, color: Theme::MUTED)
          button("Connect", x + 656, y + 442, 266, primary: true) do
            begin
              address, pin, code = parse_invite(endpoint.text.strip, fingerprint.text.strip)
              preferences["endpoint"] = address
              preferences["fingerprint"] = pin
              hide_overlay
              connect_to(address, name: name.text, fingerprint: pin, pending: code && {type: "join", code: code})
            rescue URI::InvalidURIError, RuleError => error
              notify(error.message)
            end
          end
          button("Host for friends", x + 36, y + 442, 250) do
            preferences["name"] = Protocol.name(name.text)
            hide_overlay
            play_local(hosting: true)
          rescue RuleError => error
            notify(error.message)
          end
          line(x + 36, y + 513, x + 922, y + 513)
          label("Hosting uses one port: 4388. On the internet, forward that port or run bin/server on a VPS.", x + 36, y + 537, 890, size: 13, color: Theme::MUTED)
        end
      end

      def parse_invite(text, fingerprint)
        if text.start_with?("burrow://")
          uri = URI.parse(text)
          raise RuleError, "The invite needs a host, port, and room code." unless uri.host && uri.port && uri.path.match?(%r{\A/[A-Z2-9]{6}\z})
          query = URI.decode_www_form(uri.query.to_s).to_h
          ["tls://#{uri.host}:#{uri.port}", query.fetch("fingerprint", ""), uri.path.delete_prefix("/")]
        else
          [text, fingerprint, nil]
        end
      end

      def show_create_room
        overlay("Make room for trouble", "Private room passwords are optional.", width: 760, height: 450) do |x, y|
          label("Room name", x + 34, y + 125, 600, size: 14)
          name = input("#{preferences['name']}'s brigade"[0, 24], x + 34, y + 152, 692)
          label("Room password", x + 34, y + 215, 600, size: 14)
          password = input("", x + 34, y + 242, 440, secret: true)
          label("Computers", x + 500, y + 215, 200, size: 14)
          bots = select(%w[0 1 2 3 4 5], "1", x + 500, y + 242, 226)
          button("Create room", x + 456, y + 354, 270, primary: true) do
            action("create", name: name.text, password: password.text, bots: bots.text.to_i, config: preferences["config"])
            hide_overlay
          end
        end
      end

      def show_join_code(code = "")
        overlay("Your crew is waiting", "Ask your host for the six-character room code.", width: 760, height: 425) do |x, y|
          label("Room code", x + 34, y + 128, 300, size: 14)
          code_field = input(code, x + 34, y + 156, 310)
          label("Password, if needed", x + 382, y + 128, 310, size: 14)
          password = input("", x + 382, y + 156, 342, secret: true)
          button("Join room", x + 454, y + 317, 270, primary: true) do
            action("join", code: code_field.text.strip.upcase, password: password.text)
            hide_overlay
          end
        end
      end

      def show_settings
        overlay("Make yourself comfortable", "Sound, motion, and your name are saved on this computer.", width: 960, height: 650) do |x, y|
          label("Your name", x + 36, y + 133, 450, size: 17, font: Theme.display)
          name = input(preferences["name"], x + 540, y + 125, 384)
          settings_toggle("Master sound", "All game audio. Press M during battle to mute or unmute.", "muted", x, y + 197, inverted: true)
          settings_toggle("Music", "An original, gently mischievous soundtrack.", "music", x, y + 277)
          settings_toggle("Animated effects", "Turn off animated poses, scenery drift, and extra particles.", "motion", x, y + 357)
          settings_toggle("Trusted LAN connections", "Allow unencrypted tcp:// connections on your local network.", "allow_lan", x, y + 437)
          label("Volume", x + 36, y + 530, 220, size: 17, font: Theme.display)
          select(%w[0% 25% 50% 75% 100%], "#{(preferences['volume'] * 100 / 25).round * 25}%", x + 280, y + 522, 180) do |control|
            preferences["volume"] = control.text.to_i / 100.0
            @audio.refresh
            @audio.play("pickup")
          end
          button("Save settings", x + 670, y + 560, 254, primary: true) do
            preferences["name"] = Protocol.name(name.text)
            hide_overlay
            draw_page if @page == :menu
            notify("Settings saved. Name changes apply when you connect as a new player.")
          rescue RuleError, SystemCallError => error
            notify(error.message)
          end
          label(@audio.available ? "Audio ready" : "Audio unavailable in this environment", x + 36, y + 597, 590, size: 12, color: Theme::MUTED)
        end
      end

      def settings_toggle(title, detail, key, x, y, inverted: false)
        label(title, x + 36, y, 580, size: 18, font: Theme.display)
        label(detail, x + 36, y + 30, 680, size: 13, color: Theme::MUTED)
        enabled = inverted ? !preferences[key] : preferences[key]
        control = nil
        control = button(enabled ? "On" : "Off", x + 780, y + 6, 144, selected: enabled, height: 32) do
          preferences[key] = !preferences[key]
          value = inverted ? !preferences[key] : preferences[key]
          control.text = value ? "On" : "Off"
          control.color = value ? "#d6e6dd" : Theme::WELL
          @audio.refresh
        end
      end

      def show_rules(readonly: false, tab: "Battle")
        @rules_draft ||= JSON.parse(JSON.generate(room ? room["config"] : preferences["config"]))
        draft = @rules_draft
        overlay("Your match, your rules", readonly ? "Only the host can change the rules before a match." : "Changing the rules resets everybody's ready check.", width: 1200, height: 766) do |x, y|
          %w[Battle World Arsenal].each_with_index do |name, i|
            button(name, x + 32 + i * 164, y + 112, 152, height: 32, selected: name == tab) { show_rules(readonly: readonly, tab: name) }
          end
          if tab == "Battle"
            rules_select("Grubs per team", "worms", (1..6).to_a, x + 36, y + 186, draft)
            rules_select("Starting health", "health", [50, 75, 100, 125, 150, 200], x + 640, y + 186, draft)
            rules_select("Seconds per turn", "turn_seconds", [15, 20, 30, 45, 60, 90], x + 36, y + 284, draft)
            rules_select("Seconds to retreat", "retreat_seconds", [0, 2, 3, 4, 5, 8, 10], x + 640, y + 284, draft)
            rules_select("Rounds before sudden death", "round_limit", [3, 5, 8, 10, 12, 15, 20, 30], x + 36, y + 382, draft)
            rules_select("Damage multiplier", "damage", [0.5, 0.75, 1.0, 1.25, 1.5, 2.0], x + 640, y + 382, draft)
            rules_select("Fall damage", "fall_damage", [true, false], x + 36, y + 480, draft)
            rules_select("Friendly fire", "friendly_fire", [true, false], x + 640, y + 480, draft)
            label("Sudden death sets all survivors to one health and raises the water each turn.", x + 36, y + 593, 1100, size: 14, color: Theme::MUTED)
          elsif tab == "World"
            rules_select("Landscape", "biome", Config::CHOICES["biome"], x + 36, y + 186, draft)
            rules_select("Map shape", "terrain", Config::CHOICES["terrain"], x + 640, y + 186, draft)
            rules_select("Gravity multiplier", "gravity", [0.4, 0.6, 0.8, 1.0, 1.2, 1.6], x + 36, y + 284, draft)
            rules_select("Wind strength", "wind", [0.0, 0.5, 1.0, 1.5, 2.0], x + 640, y + 284, draft)
            rules_select("Starting mines", "mines", [0, 2, 4, 6, 8, 12], x + 36, y + 382, draft)
            rules_select("Starting barrels", "barrels", [0, 2, 3, 4, 6, 12], x + 640, y + 382, draft)
            rules_select("Supply drops", "crates", [true, false], x + 36, y + 480, draft)
            rules_select("Sudden-death water rise", "water_rise", [0, 6, 12, 20, 30, 40], x + 640, y + 480, draft)
            rules_select("Battlefield size", "map_size", Config::CHOICES["map_size"], x + 640, y + 566, draft)
            label("Map seed", x + 36, y + 566, 160, size: 14)
            field = input(draft["seed"], x + 36, y + 598, 360) { |control| draft["seed"] = control.text }
            button("Random seed", x + 410, y + 598, 180) { field.text = draft["seed"] = SecureRandom.hex(4) }
          else
            label("Arsenal preset", x + 36, y + 170, 250, size: 14)
            select(%w[full classic sandbox], draft["scheme"], x + 220, y + 159, 230) do |control|
              draft["scheme"] = control.text
              draft["ammo"] = {}
              show_rules(readonly: readonly, tab: tab)
            end
            label("−1 means unlimited · 0 removes the weapon", x + 500, y + 170, 650, size: 13, color: Theme::MUTED)
            inventory = Catalog.inventory(draft["scheme"], draft["ammo"])
            Catalog::WEAPONS.values.each_with_index do |weapon, i|
              col, row = i % 4, i / 4
              lx, ly = x + 36 + col * 282, y + 216 + row * 34
              label(weapon[:name], lx, ly + 5, 184, size: 12)
              current = inventory[weapon[:id]].to_s
              choices = (%w[-1 0 1 2 3 4 5 10 20 99] + [current]).uniq
              select(choices, current, lx + 187, ly, 76) { |control| draft["ammo"][weapon[:id]] = control.text.to_i }
            end
          end
          line(x + 32, y + 660, x + 1168, y + 660)
          button("Import rules", x + 36, y + 688, 168) { import_rules(readonly: readonly, tab: tab) } unless readonly
          button("Export rules", x + 218, y + 688, 168) { export_rules(draft) }
          unless readonly
            button("Apply rules", x + 880, y + 688, 282, primary: true) do
              begin
                config = Config.new(draft).to_h
                preferences["config"] = config
                action("configure", config: config) if room
                hide_overlay
                notify("Rules saved.")
              rescue RuleError, SystemCallError => error
                notify(error.message)
              end
            end
          end
        end
      end

      def rules_select(title, key, values, x, y, draft)
        label(title, x, y, 480, size: 16, font: Theme.display)
        strings = values.map(&:to_s)
        strings << draft[key].to_s unless strings.include?(draft[key].to_s)
        select(strings, draft[key].to_s, x, y + 33, 490) do |control|
          draft[key] = case Config::DEFAULT[key]
          when Integer then control.text.to_i
          when Float then control.text.to_f
          when TrueClass, FalseClass then control.text == "true"
          else control.text
          end
        end
      end

      def export_rules(draft)
        path = @shoes.ask_save_file
        return unless path
        File.write(path, JSON.pretty_generate(Config.new(draft).to_h) + "\n", encoding: Encoding::UTF_8)
        notify("Rules exported.")
      rescue RuleError, SystemCallError => error
        notify(error.message)
      end

      def import_rules(readonly:, tab:)
        path = @shoes.ask_open_file
        return unless path
        raise RuleError, "Rule files must be smaller than 32 KB." if File.size(path) > 32_768
        @rules_draft = Config.new(JSON.parse(File.read(path, encoding: Encoding::UTF_8))).to_h
        show_rules(readonly: readonly, tab: tab)
      rescue RuleError, SystemCallError, JSON::ParserError => error
        notify("Could not import: #{error.message}")
      end

      def show_arsenal(browse: false, group: "All")
        @arsenal_pick ||= @selected_weapon
        overlay("The toy box", browse ? "48 very questionable ideas. Pick one to learn what it does." : "Choose your next bright idea. Ammo belongs to your team.", width: 1300, height: 820) do |x, y|
          box(x + 14, y + 118, 184, 524, color: Theme::WELL, radius: 10)
          (["All"] + Catalog::GROUPS).each_with_index do |name, i|
            button(name, x + 26, y + 126 + i * 41, 158, height: 32, selected: name == group) { show_arsenal(browse: browse, group: name) }
          end
          weapons = Catalog::WEAPONS.values.select { |w| group == "All" || w[:group] == group }
          weapons.each_with_index do |weapon, i|
            col, row = i % 5, i / 5
            bx, by = x + 207 + col * 211, y + 124 + row * 52
            box(bx, by, 38, 38, color: weapon[:id] == @arsenal_pick ? "#d6e6dd" : Theme::WELL, radius: 8)
            image("weapons/#{weapon[:id]}", bx + 1, by + 1, 36, 36)
            ammo = browse ? weapon[:ammo] : (my_inventory || {}).fetch(weapon[:id], 0)
            text = "#{weapon[:name]} #{ammo < 0 ? '∞' : ammo}"
            control = button(text, bx + 41, by, 165, height: 38, selected: weapon[:id] == @arsenal_pick) do
              @arsenal_pick = weapon[:id]
              show_arsenal(browse: browse, group: group)
            end
            control.style(size: px(12), tooltip: weapon[:description])
          end
          box(x + 14, y + 668, 1272, 138, color: Theme::WELL, radius: 12)
          line(x + 26, y + 659, x + 1274, y + 659)
          weapon = Catalog.fetch(@arsenal_pick)
          image("weapons/#{weapon[:id]}", x + 36, y + 681, 78, 78)
          label(weapon[:name], x + 132, y + 679, 850, size: 25, font: Theme.display)
          label(weapon[:description], x + 134, y + 720, 850, size: 14, color: Theme::MUTED)
          label(Catalog.hint(weapon[:id]), x + 134, y + 762, 850, size: 12, color: Theme::TEAL)
          unless browse
            equip = button("Equip", x + 1020, y + 741, 250, primary: true) do
              next unless equip_weapon(@arsenal_pick)
              hide_overlay
              refresh_match_hud
            end
            equip.state = "disabled" unless can_equip?(@arsenal_pick)
            reason = if state && state["shots_left"] > 0 && @arsenal_pick != "shotgun"
              "Finish your second shot first"
            elsif state&.dig("config", "terrain") == "cavern" && Catalog::SKY.include?(weapon[:kind])
              "Air support cannot reach caverns"
            elsif (my_inventory || {}).fetch(@arsenal_pick, 0).zero? && !(state && state["shots_left"] > 0 && @arsenal_pick == "shotgun")
              "Out of ammo"
            elsif !my_turn? || state["phase"] != "aiming"
              "Available on your next turn"
            end
            label(reason, x + 998, y + 704, 280, size: 11, color: Theme::MUTED, align: "center") if reason
          end
        end
      end

      def show_guide
        overlay("Small grubs. Big plans.", "Be the last team with a grub above water. Every crater changes your next move.", width: 1100, height: 750) do |x, y|
          steps = [
            ["01", "Get your bearings", "Each team takes a turn. Your active grub has an orange arrow.\nA / D moves. W jumps; B backflips. G shows the map; F follows."],
            ["02", "Make an educated guess", "Point to aim. Hold Space or mouse for throws; release to fire.\nGuns and tools use a tap. Up / Down adjusts aim."],
            ["03", "Know your next move", "E opens the arsenal. 1–5 sets grenade fuses. Homing: click to lock,\nthen aim and charge. Critters: Space activates the next stage."],
            ["04", "Have an exit strategy", "You get a few seconds to retreat after firing. Keep moving.\nWater is lethal. The last surviving team wins; sudden death raises the tide."]
          ]
          steps.each_with_index do |(number, title, detail), i|
            top = y + 137 + i * 116
            label(number, x + 40, top + 2, 80, size: 28, font: Theme.mono, color: Theme::TEAL)
            label(title, x + 132, top, 850, size: 22, font: Theme.display)
            label(detail, x + 132, top + 38, 900, size: 15, color: Theme::MUTED)
          end
          line(x + 36, y + 622, x + 1064, y + 622)
          label("Camera: Q / R zooms. Middle-drag pans. G opens the map.\nRope: ↑↓ reels, ←→ swings. Captain wool: ←→ turns. Space releases.", x + 40, y + 650, 760, size: 13, color: Theme::MUTED)
          button("Got it", x + 848, y + 654, 216, primary: true) { hide_overlay }
        end
      end

      def show_match_menu
        overlay("Catch your breath", "Online matches keep moving while this menu is open.", width: 640, height: 505) do |x, y|
          button("Back to battle", x + 38, y + 132, 564, primary: true) { hide_overlay }
          button("How to play", x + 38, y + 192, 564) { show_guide }
          button("Sound & settings", x + 38, y + 252, 564) { show_settings }
          button("Room chat", x + 38, y + 312, 564) { show_chat }
          button("Leave match", x + 38, y + 392, 564, danger: true) { confirm_leave }
        end
      end

      def show_chat
        overlay("A little friendly banter", "Messages are visible to everyone in your room.", width: 860, height: 600) do |x, y|
          box(x + 32, y + 126, 796, 352, color: Theme::WELL, radius: 10)
          @chat_log = @shoes.stack(left: px(x + 36), top: px(y + 130), width: px(788), height: px(344), scroll: true) do
            @chat_content = @shoes.para("", width: px(754), size: px(15), font: Theme.sans,
              stroke: Theme::INK, margin: px(12))
          end
          @chat_field = input("", x + 36, y + 508, 650)
          @chat_field.finish = proc { send_chat }
          button("Send", x + 704, y + 508, 120, primary: true) { send_chat }
          micro("ENTER TO SEND  ·  SCROLL FOR EARLIER MESSAGES", x + 38, y + 563, 780)
          refresh_chat
        end
      end

      def refresh_chat
        return unless @chat_log && room && @chat_signature != room["messages"]
        at_bottom = @chat_log.scroll_top + px(12) >= @chat_log.scroll_max
        @chat_signature = room["messages"]
        text = @chat_signature.empty? ? "No messages yet. Say hello to your crew." :
          @chat_signature.map { |m| "#{m['name']}: #{m['text']}" }.join("\n\n")
        set_text(@chat_content, text)
        @chat_log.scroll_top = 1_000_000 if at_bottom
      end

      def confirm_leave
        overlay("Leave this match?", "Your remaining grubs will surrender. Your friends can keep playing.", width: 740, height: 320) do |x, y|
          button("Keep playing", x + 36, y + 223, 312) { hide_overlay }
          button("Leave match", x + 382, y + 223, 322, primary: true) { leave_room }
        end
      end

      def show_result
        winner = state["teams"].find { |team| team["id"] == state["winner"] }
        overlay(winner ? "#{short_text(winner['name'], 24)} takes the island!" : "A spectacular draw!", "Good friends. Questionable tactics. One very different island.", width: 1100, height: 720) do |x, y|
          color = winner ? COLORS[winner["color"]] : Theme::GOLD
          panel(x + 32, y + 132, 302, 420, color: Theme::INK)
          micro(winner ? "ISLAND CHAMPIONS" : "NOBODY LEFT STANDING", x + 52, y + 153, 262, color: Theme::GOLD)
          box(x + 77, y + 220, 212, 212, color: color + "30", radius: 106)
          grub(winner ? winner["color"] : 0, x + 46, y + 181, size: 276, state: "victory", frame: 2)
          label(winner ? short_text(winner["name"], 24) : "Mutual destruction", x + 49, y + 446, 268,
            size: 25, font: Theme.display, color: Theme::WHITE, align: "center")
          survivors = state["worms"].count { |w| winner && w["team"] == winner["id"] && w["hp"] > 0 }
          label(winner ? "#{survivors} grub#{survivors == 1 ? '' : 's'} still standing" : "A rematch should settle it.",
            x + 49, y + 490, 268, size: 14, color: "#b6cdcb", align: "center")
          micro("THE DAMAGE REPORT", x + 362, y + 143, 380, color: Theme::TEAL)
          micro("DAMAGE", x + 950, y + 143, 110)
          teams = state["teams"].sort_by { |t| [t["id"] == state["winner"] ? 0 : 1, -t["score"]] }
          row_height = [372.0 / teams.length, 98].min
          teams.each_with_index do |team, i|
            top = y + 176 + i * row_height
            winning = team["id"] == state["winner"]
            box(x + 352, top, 714, row_height - 8, color: winning ? "#e2ece3" : Theme::WELL, radius: 10)
            box(x + 364, top + 13, 3, row_height - 34, color: COLORS[team["color"]], radius: 1)
            grub(team["color"], x + 375, top + (row_height - 56) / 2 - 5, size: 50)
            label(short_text(team["name"], 30), x + 436, top + 12, 430, size: 19, font: Theme.display)
            count = state["worms"].count { |w| w["team"] == team["id"] && w["hp"] > 0 }
            label(winning ? "Winner · #{count} surviving" : "#{count} surviving", x + 438, top + 39, 440,
              size: 11, color: Theme::MUTED) if row_height >= 60
            label(team["score"].to_s, x + 921, top + (row_height - 36) / 2, 119, size: 22,
              font: Theme.mono, color: winning ? Theme::TEAL : Theme::INK, align: "right")
          end
          line(x + 32, y + 577, x + 1068, y + 577)
          label("#{state['round']} round#{state['round'] == 1 ? '' : 's'}  ·  #{state['turn']} turns  ·  #{state.dig('config', 'biome').capitalize}",
            x + 38, y + 594, 490, size: 14, font: Theme.display)
          micro("SEED  #{short_text(state.dig('config', 'seed'), 38)}", x + 550, y + 597, 512)
          button("View the battlefield", x + 36, y + 646, 256) { hide_overlay }
          button("Leave room", x + 308, y + 646, 226) { leave_room }
          if room_host?
            button("Play another", x + 760, y + 644, 304, height: 42, primary: true) { action("rematch"); hide_overlay }
          else
            label("Waiting for your host to start another.", x + 724, y + 655, 340, size: 13, color: Theme::MUTED)
          end
        end
      end
    end
  end
end
