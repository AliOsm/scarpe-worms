# frozen_string_literal: true

module Burrow
  module Client
    module Dialogs
      def overlay(title, subtitle = "", width: 1060, height: 700, &body)
        cancel_controls
        @audio&.play("open", volume: 0.4) unless @overlay
        @chat_log = @chat_content = @chat_signature = @arsenal = nil
        @overlay = title
        @content.style(inert: true)
        @modal.show
        @modal.clear do
          box(0, 0, 1440, 900, color: "#020b1cc4", radius: 0)
          @dialog_x, @dialog_y = (1440 - width) / 2, (900 - height) / 2
          frame(@dialog_x, @dialog_y, width, height, title: title, title_size: 30)
          label(subtitle, @dialog_x + 60, @dialog_y + 84, width - 120, size: 14, color: "#e3f1ff", align: "center") unless subtitle.empty?
          back_control(@dialog_x - 50, @dialog_y + 2) { hide_overlay }
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
        @arsenal = nil
        place_toast
      end

      def show_connect
        overlay("A little multiplayer mayhem", "Connect to a host, paste an invite, or host your own room.", width: 960, height: 600) do |x, y|
          field_label("Your name", x + 36, y + 120, 330)
          name = input(preferences["name"], x + 36, y + 148, 350)
          field_label("Server address or invite", x + 36, y + 206, 740)
          endpoint = input(preferences["endpoint"], x + 36, y + 234, 886)
          field_label("Certificate fingerprint (for a self-hosted server)", x + 36, y + 292, 850)
          fingerprint = input(preferences["fingerprint"], x + 36, y + 320, 886)
          label("A burrow:// invite fills in the server, room, and fingerprint for you.", x + 36, y + 378, 880, size: 14, color: "#e3f1ff")
          button("Connect", x + 656, y + 436, 266, height: 46, primary: true, size: 18) do
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
          button("Host for friends", x + 36, y + 436, 260, height: 46, size: 18) do
            preferences["name"] = Protocol.name(name.text)
            hide_overlay
            play_local(hosting: true)
          rescue RuleError => error
            notify(error.message)
          end
          well(x + 28, y + 510, 904, 62, radius: 16)
          label("Hosting uses one port: 4388. On the internet, forward that port or run bin/server on a VPS.", x + 48, y + 532, 870, size: 13, color: Theme::MUTED)
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
          field_label("Room name", x + 34, y + 120, 600)
          name = input("#{preferences['name']}'s brigade"[0, 24], x + 34, y + 148, 692)
          field_label("Room password", x + 34, y + 210, 600)
          password = input("", x + 34, y + 238, 440, secret: true)
          field_label("Computers", x + 500, y + 210, 200)
          bots = select(%w[0 1 2 3 4 5], "1", x + 500, y + 239, 226)
          button("Create room", x + 456, y + 350, 270, height: 46, primary: true, size: 18) do
            action("create", name: name.text, password: password.text, bots: bots.text.to_i, config: preferences["config"])
            hide_overlay
          end
        end
      end

      def show_join_code(code = "")
        overlay("Your crew is waiting", "Ask your host for the six-character room code.", width: 760, height: 425) do |x, y|
          field_label("Room code", x + 34, y + 122, 300)
          code_field = input(code, x + 34, y + 150, 310)
          field_label("Password, if needed", x + 382, y + 122, 310)
          password = input("", x + 382, y + 150, 342, secret: true)
          button("Join room", x + 454, y + 322, 270, height: 46, primary: true, size: 18) do
            action("join", code: code_field.text.strip.upcase, password: password.text)
            hide_overlay
          end
        end
      end

      def show_settings
        overlay("Make yourself comfortable", "Sound, movement, and your name are saved on this computer.", width: 960, height: 740) do |x, y|
          field_label("Your name", x + 36, y + 133, 450, size: 19)
          name = input(preferences["name"], x + 540, y + 125, 384)
          settings_toggle("Master sound", "All game audio. Press M during battle to mute or unmute.", "muted", x, y + 197, inverted: true)
          settings_toggle("Music", "An original, gently mischievous soundtrack.", "music", x, y + 277)
          settings_toggle("Animated effects", "Turn off animated poses, scenery drift, and extra particles.", "motion", x, y + 357)
          settings_toggle("Responsive movement", "Experimental: walking and jumps respond sooner. Turn off to compare.", "predict_movement", x, y + 437)
          settings_toggle("Trusted LAN connections", "Allow unencrypted tcp:// connections on your local network.", "allow_lan", x, y + 517)
          field_label("Volume", x + 36, y + 610, 220, size: 19)
          select(%w[0% 25% 50% 75% 100%], "#{(preferences['volume'] * 100 / 25).round * 25}%", x + 280, y + 602, 180) do |control|
            preferences["volume"] = control.text.to_i / 100.0
            @audio.refresh
            @audio.play("pickup")
          end
          button("Save settings", x + 670, y + 648, 254, height: 46, primary: true, size: 18) do
            preferences["name"] = Protocol.name(name.text)
            hide_overlay
            draw_page if @page == :menu
            notify("Settings saved. Name changes apply when you connect as a new player.")
          rescue RuleError, SystemCallError => error
            notify(error.message)
          end
          label(@audio.available ? "Audio ready" : "Audio unavailable in this environment", x + 36, y + 696, 590, size: 12, color: Theme::MUTED)
        end
      end

      def settings_toggle(title, detail, key, x, y, inverted: false)
        field_label(title, x + 36, y, 580, size: 19)
        label(detail, x + 36, y + 30, 680, size: 13, color: "#e3f1ff")
        enabled = inverted ? !preferences[key] : preferences[key]
        control = nil
        control = button(enabled ? "On" : "Off", x + 780, y + 4, 144, height: 36, tone: enabled ? :green : :navy) do
          preferences[key] = !preferences[key]
          @prediction&.clear_inputs if key == "predict_movement"
          value = inverted ? !preferences[key] : preferences[key]
          control.text = value ? "On" : "Off"
          control.tone = value ? :green : :navy
          @audio.refresh
        end
      end

      def show_rules(readonly: false, tab: "Battle")
        @rules_draft ||= JSON.parse(JSON.generate(room ? room["config"] : preferences["config"]))
        draft = @rules_draft
        overlay("Your match, your rules", readonly ? "Only the host can change the rules before a match." : "Changing the rules resets everybody's ready check.", width: 1200, height: 766) do |x, y|
          %w[Battle World Arsenal].each_with_index do |name, i|
            button(name, x + 36 + i * 164, y + 114, 152, height: 36, selected: name == tab) { show_rules(readonly: readonly, tab: name) }
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
            label("Sudden death sets all survivors to one health and raises the water each turn.", x + 36, y + 593, 1100, size: 14, color: "#e3f1ff")
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
            field_label("Map seed", x + 36, y + 566, 160)
            field = input(draft["seed"], x + 36, y + 599, 360) { |control| draft["seed"] = control.text }
            button("Random seed", x + 410, y + 598, 180) { field.text = draft["seed"] = SecureRandom.hex(4) }
          else
            field_label("Arsenal preset", x + 36, y + 168, 250)
            select(%w[full classic sandbox], draft["scheme"], x + 220, y + 159, 230) do |control|
              draft["scheme"] = control.text
              draft["ammo"] = {}
              show_rules(readonly: readonly, tab: tab)
            end
            label("−1 means unlimited · 0 removes the weapon", x + 500, y + 170, 650, size: 13, color: "#e3f1ff")
            inventory = Catalog.inventory(draft["scheme"], draft["ammo"])
            Catalog::WEAPONS.values.each_with_index do |weapon, i|
              col, row = i % 4, i / 4
              lx, ly = x + 36 + col * 282, y + 216 + row * 34
              label(weapon[:name], lx, ly + 6, 184, size: 13, font: Theme.display, weight: 600)
              current = inventory[weapon[:id]].to_s
              choices = (%w[-1 0 1 2 3 4 5 10 20 99] + [current]).uniq
              select(choices, current, lx + 187, ly, 76) { |control| draft["ammo"][weapon[:id]] = control.text.to_i }
            end
          end
          line(x + 32, y + 664, x + 1168, y + 664, color: "#ffffff40", width: 2)
          button("Import rules", x + 36, y + 690, 168) { import_rules(readonly: readonly, tab: tab) } unless readonly
          button("Export rules", x + 218, y + 690, 168) { export_rules(draft) }
          unless readonly
            button("Apply rules", x + 880, y + 686, 282, height: 46, primary: true, size: 18) do
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
        field_label(title, x, y, 480)
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

      # The arsenal, after classic weapon panels: one row per family of toys.
      def show_arsenal(browse: false)
        @arsenal_pick ||= @selected_weapon
        overlay("The toy box", browse ? "48 very questionable ideas. Pick one to learn what it does." : "Choose your next bright idea. Ammo belongs to your team.", width: 1300, height: 820) do |x, y|
          @arsenal = {browse: browse, slots: {}, rows: []}
          well(x + 24, y + 112, 822, 690)
          Catalog::GROUPS.each_with_index do |group, row|
            top = y + 120 + row * 68
            ids = Catalog::WEAPONS.values.select { |w| w[:group] == group }.map { |w| w[:id] }
            @arsenal[:rows] << ids
            label(group, x + 36, top + 21, 140, size: 15, color: Theme::YELLOW, font: Theme.display, weight: 700, align: "right")
            ids.each_with_index { |id, col| arsenal_slot(id, x + 194 + col * 80, top + 4) }
          end
          well(x + 868, y + 112, 408, 690)
          detail = @arsenal[:detail] = {}
          detail[:icon] = image("weapons/#{@arsenal_pick}", x + 992, y + 140, 160, 160)
          detail[:name] = outlined("", x + 884, y + 318, 376, size: 28, color: Theme::CYAN, align: "center", thickness: 2)
          detail[:meta] = label("", x + 884, y + 364, 376, size: 15, color: Theme::YELLOW, font: Theme.display, weight: 700, align: "center")
          detail[:description] = label("", x + 900, y + 404, 344, size: 16, color: "#e3f1ff", align: "center")
          detail[:hint] = label("", x + 900, y + 520, 344, size: 13, color: Theme::CYAN, align: "center")
          unless browse
            detail[:reason] = label("", x + 884, y + 680, 376, size: 12, color: Theme::MUTED, align: "center")
            detail[:equip] = button("Equip", x + 904, y + 716, 336, height: 54, primary: true, size: 22) do
              next unless equip_weapon(@arsenal_pick)
              hide_overlay
              refresh_match_hud
            end
          end
          arsenal_pick(@arsenal_pick)
        end
      end

      def arsenal_slot(id, x, y)
        weapon = Catalog.fetch(id)
        ammo = @arsenal[:browse] ? weapon[:ammo] : (my_inventory || {}).fetch(id, 0)
        ring = @shoes.oval(px(x), px(y), px(58), px(58), fill: shade("#09203f", "#123a6e"), stroke: "#06142b", strokewidth: px(2))
        icon = image("weapons/#{id}", x + 6, y + 6, 46, 46, alt: "#{weapon[:name]}, #{ammo < 0 ? 'unlimited' : "#{ammo} left"}",
          tooltip: weapon[:name])
        box(x + 1, y + 1, 56, 56, color: "#0b2350b0", radius: 28) if ammo.zero?
        outlined("x#{ammo}", x - 8, y - 7, 60, size: 15, color: ammo.zero? ? Theme::DIM : Theme::ORANGE,
          thickness: 1.5, offsets: Theme::OUTLINE.first(4)) unless ammo.negative?
        [ring, icon].each { |node| node.click { arsenal_pick(id) } }
        @arsenal[:slots][id] = ring
      end

      def arsenal_pick(id)
        return unless @arsenal
        if (previous = @arsenal[:slots][@arsenal_pick]) && @arsenal_pick != id
          previous.style(fill: shade("#09203f", "#123a6e"), stroke: "#06142b", strokewidth: px(2))
        end
        @arsenal_pick = id
        @arsenal[:slots][id]&.style(fill: shade("#2c74d6", "#0f3a80"), stroke: Theme::YELLOW, strokewidth: px(4))
        weapon = Catalog.fetch(id)
        detail = @arsenal[:detail]
        detail[:icon].path = File.join(Theme::ART, "weapons/#{id}.png")
        detail[:name].text = weapon[:name]
        ammo = @arsenal[:browse] ? weapon[:ammo] : (my_inventory || {}).fetch(id, 0)
        set_text(detail[:meta], "#{weapon[:group]} · #{ammo < 0 ? 'Unlimited' : "#{ammo} in the box"}")
        set_text(detail[:description], weapon[:description])
        set_text(detail[:hint], Catalog.hint(id))
        return unless (equip = detail[:equip])
        equip.state = can_equip?(id) ? nil : "disabled"
        reason = if state && state["shots_left"] > 0 && id != "shotgun"
          "Finish your second shot first"
        elsif state&.dig("config", "terrain") == "cavern" && Catalog::SKY.include?(weapon[:kind])
          "Air support cannot reach caverns"
        elsif (my_inventory || {}).fetch(id, 0).zero? && !(state && state["shots_left"] > 0 && id == "shotgun")
          "Out of ammo"
        elsif !my_turn? || state["phase"] != "aiming"
          "Available on your next turn"
        end
        set_text(detail[:reason], reason.to_s)
      end

      # Arrow keys walk the arsenal grid; Return equips the highlighted toy.
      def arsenal_key(key)
        rows = @arsenal[:rows]
        row = rows.index { |ids| ids.include?(@arsenal_pick) } || 0
        col = rows[row].index(@arsenal_pick) || 0
        case key
        when "left", "right"
          col = (col + (key == "right" ? 1 : -1)) % rows[row].length
        when "up", "down"
          row = (row + (key == "down" ? 1 : -1)) % rows.length
          col = col.clamp(0, rows[row].length - 1)
        when "enter", " "
          if !@arsenal[:browse] && equip_weapon(@arsenal_pick)
            hide_overlay
            refresh_match_hud
          end
          return
        else
          return
        end
        arsenal_pick(rows[row][col])
      end

      def show_guide
        overlay("Small grubs. Big plans.", "Be the last team with a grub above water. Every crater changes your next move.", width: 1100, height: 750) do |x, y|
          steps = [
            ["01", "Get your bearings", "Each team takes a turn. Your active grub has an orange arrow.\nA / D moves. W jumps; B backflips. G shows the map; F follows."],
            ["02", "Make an educated guess", "Point to aim. Hold Space or mouse for throws; release to fire.\nGuns and tools use a tap. Up / Down adjusts aim."],
            ["03", "Know your next move", "E opens the arsenal. 1–5 sets fuses. Homing: click to lock, then aim and charge.\n← → picks an air strike's approach or tilts a girder. Space triggers the next stage."],
            ["04", "Have an exit strategy", "You get a few seconds to retreat. Blasts fling grubs, barrels and mines; fire spreads.\nWater is lethal. The last surviving team wins; sudden death raises the tide."]
          ]
          steps.each_with_index do |(number, title, detail), i|
            top = y + 137 + i * 116
            well(x + 32, top - 10, 1036, 104, radius: 20)
            outlined(number, x + 52, top + 14, 80, size: 38, color: Theme::CYAN, thickness: 2)
            label(title, x + 136, top, 850, size: 22, font: Theme.display, weight: 700, color: Theme::YELLOW)
            label(detail, x + 136, top + 36, 900, size: 15, color: "#e3f1ff")
          end
          label("Camera: Q / R or pinch zooms. Middle-drag pans; drag the minimap to move the view. G opens the map.\nRope: ↑↓ reels, ←→ swings. Captain wool: ←→ turns. Space releases.", x + 40, y + 650, 760, size: 13, color: "#e3f1ff")
          button("Got it", x + 848, y + 650, 216, height: 48, primary: true, size: 20) { hide_overlay }
        end
      end

      def show_match_menu
        overlay("Catch your breath", "Online matches keep moving while this menu is open.", width: 640, height: 505) do |x, y|
          well(x + 60, y + 118, 520, 350)
          menu_item("Back to battle", x + 70, y + 136, 500, height: 56, size: 30, selected: true) { hide_overlay }
          menu_item("How to play", x + 70, y + 198, 500, height: 56, size: 30) { show_guide }
          menu_item("Sound & settings", x + 70, y + 260, 500, height: 56, size: 30) { show_settings }
          menu_item("Room chat", x + 70, y + 322, 500, height: 56, size: 30) { show_chat }
          menu_item("Leave match", x + 70, y + 396, 500, height: 56, size: 30, color: "#ff8f7a") { confirm_leave }
        end
      end

      def show_chat
        overlay("A little friendly banter", "Messages are visible to everyone in your room.", width: 860, height: 600) do |x, y|
          well(x + 32, y + 122, 796, 360)
          @chat_log = @shoes.stack(left: px(x + 38), top: px(y + 128), width: px(784), height: px(348), scroll: true) do
            @chat_content = @shoes.para("", width: px(750), size: px(15), font: Theme.sans,
              stroke: Theme::TEXT, margin: px(12))
          end
          @chat_field = input("", x + 36, y + 504, 650)
          @chat_field.finish = proc { send_chat }
          button("Send", x + 704, y + 503, 120, height: 40, primary: true) { send_chat }
          micro("ENTER TO SEND  ·  SCROLL FOR EARLIER MESSAGES", x + 38, y + 560, 780, color: "#e3f1ff")
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
          button("Keep playing", x + 36, y + 216, 312, height: 48, size: 19) { hide_overlay }
          button("Leave match", x + 382, y + 216, 322, height: 48, danger: true, size: 19) { leave_room }
        end
      end

      def show_result
        winner = state["teams"].find { |team| team["id"] == state["winner"] }
        overlay(winner ? "#{short_text(winner['name'], 24)} takes the island!" : "A spectacular draw!", "Good friends. Questionable tactics. One very different island.", width: 1100, height: 720) do |x, y|
          color = winner ? COLORS[winner["color"]] : Theme::YELLOW
          well(x + 32, y + 118, 302, 440, radius: 22)
          micro(winner ? "ISLAND CHAMPIONS" : "NOBODY LEFT STANDING", x + 52, y + 136, 262, color: Theme::YELLOW, align: "center")
          box(x + 77, y + 196, 212, 212, color: color + "40", radius: 106, stroke: color, stroke_width: 3)
          grub(winner ? winner["color"] : 0, x + 46, y + 160, size: 276, state: "victory", frame: 2)
          outlined(winner ? short_text(winner["name"], 24) : "Mutual destruction", x + 49, y + 434, 268,
            size: 26, color: color, align: "center", thickness: 2)
          survivors = state["worms"].count { |w| winner && w["team"] == winner["id"] && w["hp"] > 0 }
          label(winner ? "#{survivors} grub#{survivors == 1 ? '' : 's'} still standing" : "A rematch should settle it.",
            x + 49, y + 486, 268, size: 15, color: "#e3f1ff", align: "center")
          micro("THE DAMAGE REPORT", x + 364, y + 124, 380, color: Theme::YELLOW)
          micro("DAMAGE", x + 950, y + 124, 110, color: Theme::YELLOW, align: "right")
          teams = state["teams"].sort_by { |t| [t["id"] == state["winner"] ? 0 : 1, -t["score"]] }
          row_height = [400.0 / teams.length, 98].min
          teams.each_with_index do |team, i|
            top = y + 150 + i * row_height
            winning = team["id"] == state["winner"]
            box(x + 352, top, 714, row_height - 8, color: winning ? "#1d4f9c" : Theme::NAVY, radius: 16,
              stroke: winning ? Theme::YELLOW : Theme::WELL_EDGE, stroke_width: 2)
            box(x + 366, top + 12, 5, row_height - 32, color: COLORS[team["color"]], radius: 2)
            grub(team["color"], x + 378, top + (row_height - 56) / 2 - 5, size: 50)
            label(short_text(team["name"], 30), x + 438, top + 10, 430, size: 20, font: Theme.display, weight: 700, color: COLORS[team["color"]])
            count = state["worms"].count { |w| w["team"] == team["id"] && w["hp"] > 0 }
            label(winning ? "Winner · #{count} surviving" : "#{count} surviving", x + 440, top + 38, 440,
              size: 12, color: Theme::MUTED) if row_height >= 60
            outlined(team["score"].to_s, x + 900, top + (row_height - 44) / 2, 140, size: 26,
              color: winning ? Theme::YELLOW : Theme::WHITE, align: "right", thickness: 2)
          end
          line(x + 32, y + 578, x + 1068, y + 578, color: "#ffffff40", width: 2)
          label("#{state['round']} round#{state['round'] == 1 ? '' : 's'}  ·  #{state['turn']} turns  ·  #{state.dig('config', 'biome').capitalize}",
            x + 38, y + 594, 490, size: 16, font: Theme.display, weight: 700, color: Theme::YELLOW)
          micro("SEED  #{short_text(state.dig('config', 'seed'), 38)}", x + 550, y + 598, 512, color: "#e3f1ff", align: "right")
          button("View the battlefield", x + 36, y + 640, 256, height: 46) { hide_overlay }
          button("Leave room", x + 308, y + 640, 226, height: 46, danger: true) { leave_room }
          if room_host?
            button("Play another", x + 760, y + 636, 304, height: 52, primary: true, size: 21) { action("rematch"); hide_overlay }
          else
            label("Waiting for your host to start another.", x + 724, y + 654, 340, size: 14, color: "#e3f1ff")
          end
        end
      end
    end
  end
end
