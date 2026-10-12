# frozen_string_literal: true

module Burrow
  module Client
    module Screens
      def draw_menu
        image("menu-scene", 0, 0, 1440, 900)
        outlined("BURROW", 66, 30, 640, size: 104, color: Theme::YELLOW, thickness: 5, shadow: 8)
        outlined("BRIGADE", 66, 138, 680, size: 104, color: Theme::ORANGE, thickness: 5, shadow: 8)
        outlined("Tiny teams. Enormous trouble.", 76, 264, 600, size: 25, thickness: 2, shadow: 3)
        frame(70, 322, 540, 476, title: "Main Menu")
        well(100, 422, 480, 344)
        [["Quick battle", -> { play_local(quick: true) }], ["Create a match", -> { play_local }],
          ["Play with friends", -> { show_connect }], ["The arsenal", -> { show_arsenal(browse: true) }],
          ["How to play", -> { show_guide }], ["Settings", -> { show_settings }]].each_with_index do |(text, go), i|
          menu_item(text, 110, 434 + i * 54, 460, height: 48, size: 27, selected: i.zero?) { go.call }
        end
        box(66, 818, 552, 72, color: Theme::INK, radius: 30)
        box(70, 822, 544, 64, color: Theme::NAVY..Theme::DEEP, radius: 27)
        grub(0, 78, 818, size: 66)
        label(short_text(preferences["name"], 22), 148, 830, 250, size: 20, font: Theme.display, weight: 700)
        micro("READY FOR MISCHIEF", 149, 859, 250, color: Theme::YELLOW)
        micro("6 TEAMS · 48 TOYS\nENDLESS ISLANDS", 410, 836, 190, color: Theme::MUTED, align: "right")
        outlined("v#{VERSION}", 1250, 860, 170, size: 16, align: "right", thickness: 1.5)
      end

      def page_header(title, subtitle, back: true)
        image("menu-scene", 0, 0, 1440, 900)
        box(0, 0, 1440, 900, color: "#06142fb8", radius: 0)
        frame(28, 18, 1384, 126, radius: 30)
        left = back ? 150 : 60
        back_control(40, 33, "Main menu", size: 13) { to_menu } if back
        micro("BURROW BRIGADE  /  ASSEMBLE YOUR CREW", left, 30, 800, color: Theme::YELLOW)
        outlined(title, left, 48, 1000, size: 40, color: Theme::CYAN, thickness: 2.5, shadow: 3)
        label(subtitle, left + 2, 104, 1000, size: 15, color: "#e3f1ff")
      end

      def draw_browser
        page_header("Find your kind of trouble", "Join a room on this server, or make one for your friends.")
        frame(28, 166, 1384, 714, title: "Open rooms", title_size: 26)
        @connection_label = label(@connection_status == "online" ? "Connected · #{@endpoint}" : @status_message || "Connecting…", 56, 248, 1050, size: 13, color: Theme::CYAN)
        well(52, 276, 1060, 524)
        button("Create room", 1136, 276, 252, height: 46, primary: true, size: 18) { show_create_room }
        button("Join with a code", 1136, 340, 252, height: 42) { show_join_code }
        micro("PRIVATE HOSTING\nNO ACCOUNT REQUIRED", 1140, 404, 248, color: "#e3f1ff")
        button("Change server", 1136, 818, 252) { show_connect }
        if @connection_status == "rejected"
          outlined("Connection needs attention", 84, 312, 900, size: 30, thickness: 2)
          label(@status_message, 86, 366, 960, size: 17, color: Theme::MUTED)
          button("Connect as a new player", 86, 430, 300, primary: true) do
            preferences["sessions"].delete(@endpoint)
            preferences["sessions"].delete(@session_key) if @session_key
            preferences.save
            connect_to(@endpoint, fingerprint: @fingerprint, pending: @pending,
              session_key: @session_key, auto_start: @auto_start)
          end
        elsif @rooms.empty?
          grub(1, 492, 300, size: 180)
          outlined("An island to yourselves", 132, 500, 900, size: 32, align: "center", thickness: 2, shadow: 3)
          label("No rooms here yet. Create one, then share the invite\nwith up to five friends. Computer teams can fill the gaps.", 132, 556, 900, size: 17, color: Theme::MUTED, align: "center")
        else
          pages = (@rooms.length / 8.0).ceil
          @browser_page = (@browser_page || 0).clamp(0, pages - 1)
          @rooms.slice(@browser_page * 8, 8).each_with_index do |entry, i|
            y = 284 + i * 64
            line(72, y + 60, 1092, y + 60, color: "#3d7fd055") unless i == 7
            label(short_text(entry["name"], 32), 74, y + 6, 570, size: 20, font: Theme.display, weight: 700, color: Theme::YELLOW)
            label("#{entry['biome'].capitalize} · #{entry['count']}/6 teams · #{entry['locked'] ? 'Private' : 'Open'}", 76, y + 34, 600, size: 13, color: Theme::MUTED)
            label(entry["stage"] == "lobby" ? "In the lobby" : "In battle", 680, y + 19, 170, size: 15, color: Theme::CYAN, font: Theme.display, weight: 600)
            control = button("Join #{entry['code']}", 876, y + 11, 210, height: 38) do
              if entry["locked"]
                show_join_code(entry["code"])
              else
                action("join", code: entry["code"])
              end
            end
            control.state = "disabled" unless entry["stage"] == "lobby" && entry["count"] < 6
          end
          if pages > 1
            previous = button("Previous", 56, 818, 132, height: 36) { @browser_page -= 1; draw_page }
            previous.state = "disabled" if @browser_page.zero?
            following = button("Next", 202, 818, 132, height: 36) { @browser_page += 1; draw_page }
            following.state = "disabled" if @browser_page == pages - 1
            label("Page #{@browser_page + 1} of #{pages} · #{@rooms.length} rooms", 356, 827, 700, size: 14, color: "#e3f1ff")
          end
        end
      end

      def draw_lobby
        page_header(room["name"], "A little preparation. A lot of consequences.", back: false)
        button("Leave room", 1212, 58, 176, height: 46, danger: true, size: 18) { leave_room }
        frame(28, 166, 520, 610, title: "Current Teams", title_size: 26)
        frame(572, 166, 840, 610, title: "The Battlefield", title_size: 26)
        label("#{room['members'].length} / 6 teams", 54, 246, 300, size: 18, color: Theme::YELLOW, font: Theme.display, weight: 700)
        well(48, 280, 480, 404)
        6.times do |i|
          y = 286 + i * 66
          member = room["members"][i]
          if member
            box(60, y + 6, 52, 52, color: COLORS[i] + "40", radius: 14, stroke: COLORS[i], stroke_width: 2)
            grub(i, 57, y, size: 59)
            label(short_text(member["name"], 22), 124, y + 8, 246, size: 19, font: Theme.display, weight: 700, color: COLORS[i])
            detail = member["bot"] ? "Computer" : member["id"] == my_id ? "You" : "Friend"
            detail += " · Host" if member["id"] == room["host_id"]
            detail += member["connected"] ? (member["ready"] || member["id"] == room["host_id"] ? " · Ready" : " · Getting ready") : " · Reconnecting"
            label(detail, 126, y + 36, 260, size: 12, color: Theme::MUTED)
            if room_host? && member["id"] != my_id
              button("Remove", 406, y + 15, 104, height: 32, danger: true, size: 14) { action("kick", player: member["id"]) }
            end
          else
            box(66, y + 12, 40, 40, color: "#ffffff10", radius: 20, stroke: "#3d7fd0", stroke_width: 2)
            label("+", 66, y + 15, 40, size: 22, color: Theme::MUTED, align: "center", font: Theme.display, weight: 700)
            label("An open spot", 124, y + 20, 230, size: 16, color: Theme::DIM, font: Theme.display)
            button("Add computer", 362, y + 15, 148, height: 32, primary: true, size: 14) { action("add_bot") } if room_host?
          end
          line(64, y + 64, 512, y + 64, color: "#3d7fd055") unless i == 5
        end
        micro("CREW CHAT", 52, 700, 320, color: Theme::YELLOW)
        button("Chat", 432, 694, 92, height: 30, size: 14) { show_chat }
        @chat_history = label(lobby_chat_preview, 52, 722, 470, size: 11, color: "#e3f1ff")
        label("#{room.dig('config', 'biome').capitalize} · #{room.dig('config', 'terrain').capitalize}", 600, 250, 560, size: 26, font: Theme.display, weight: 700, color: Theme::YELLOW)
        button("Shuffle map", 1206, 250, 180, height: 36, size: 15) { shuffle_map } if room_host?
        draw_map_preview(room["config"], 600, 300, 786, 296)
        config = room["config"]
        [["#{config['worms']} grubs each", 604], ["#{config['health']} health", 862], ["#{config['turn_seconds']} seconds / turn", 1120]].each do |text, left|
          label(text, left, 612, 262, size: 18, font: Theme.display, weight: 700)
        end
        label("#{config['scheme'].capitalize} arsenal · #{config['terrain'].capitalize} · Seed: #{config['seed']}", 604, 646, 780, size: 13, color: Theme::MUTED)
        outlined("ROOM #{room['code']}", 604, 694, 380, size: 24, color: Theme::CYAN, thickness: 2)
        button("Copy invite", 1000, 692, 186, height: 40) { copy_invite }
        button("Match rules", 1200, 692, 186, height: 40) { show_rules(readonly: !room_host?) }
        frame(28, 798, 1384, 84, radius: 26)
        draft = @lobby_draft_room == room["code"] ? @lobby_chat_field&.text.to_s : ""
        @lobby_draft_room = room["code"]
        @lobby_chat_field = input(draft, 52, 821, 364)
        @lobby_chat_field.finish = proc { send_chat(@lobby_chat_field) }
        button("Send", 432, 820, 96, height: 40) { send_chat(@lobby_chat_field) }
        if room_host?
          start = button("Start the mischief", 1034, 816, 352, height: 48, primary: true, size: 20) { action("start") }
          start.state = "disabled" if room["members"].length < 2 || room["members"].any? { |m| !m["bot"] && m["id"] != my_id && (!m["ready"] || !m["connected"]) }
          label("Friends choose Ready when they're set.", 556, 831, 460, size: 14, color: "#e3f1ff")
        else
          me = room["members"].find { |m| m["id"] == my_id }
          button(me && me["ready"] ? "Not ready yet" : "Ready to rumble", 1034, 816, 352, height: 48, tone: me && me["ready"] ? :blue : :green, size: 20) { action("ready", ready: !me["ready"]) }
          label("The host will start when everyone is ready.", 556, 831, 460, size: 14, color: "#e3f1ff")
        end
      end

      def draw_map_preview(config, x, y, width, height)
        dimensions = Config.new(config).world_size(room["members"].length)
        box(x - 4, y - 4, width + 8, height + 8, color: Theme::WELL_EDGE, radius: 14)
        box(x, y, width, height, color: Theme::DEEP, radius: 10)
        fit = [width.fdiv(dimensions[0]), height.fdiv(dimensions[1])].min
        drawn_width, drawn_height = dimensions.map { |dimension| dimension * fit }
        x += (width - drawn_width) / 2
        y += (height - drawn_height) / 2
        width, height = drawn_width, drawn_height
        image("sky-#{config['biome']}", x, y, width, height)
        signature = config.slice("seed", "terrain", "biome", "map_size").merge("dimensions" => dimensions)
        if signature != @map_preview_signature
          @map_preview_signature = signature
          @preview_art&.close
          @preview_art = TerrainArt.new
          terrain = Terrain.new(seed: Config.new(config).seed_number, shape: config["terrain"], width: dimensions[0], height: dimensions[1])
          @preview_art.request(terrain, config["biome"])
          @map_preview_path = nil
        end
        @preview_bounds = [x, y, width, height]
        @preview_layer = @shoes.stack(left: px(x), top: px(y), width: px(width), height: px(height)) {}
        @preview_image = nil
        @preview_loading = nil
        if @map_preview_path
          @preview_layer.append { @preview_image = @shoes.image(@map_preview_path, left: 0, top: 0, width: px(width), height: px(height)) }
        else
          @preview_loading = outlined("Drawing your island…", x + 24, y + height / 2 - 15, width - 48,
            size: 22, align: "center", thickness: 2)
        end
        water = (dimensions[1] - 96).fdiv(dimensions[1])
        box(x, y + height * water, width, height * (1 - water), color: "#438c97dd", radius: 0)
        box(x + 9, y + 9, 374, 28, color: "#071731d9", radius: 14)
        micro("#{dimensions[0]} × #{dimensions[1]} · #{config.fetch('map_size', 'auto').capitalize} battlefield", x + 22, y + 15, width - 38, color: Theme::WHITE)
      end

      def lobby_chat_preview
        messages = room["messages"].last(3)
        return "Say hello. Your messages are shared with the room." if messages.empty?
        messages.map { |m| short_text("#{m['name']}: #{m['text']}", 56) }.join("\n")
      end

      def update_map_preview
        return unless @preview_art && (result = @preview_art.poll)
        @map_preview_path = result[:overview]
        return unless @preview_layer
        @preview_loading&.hide
        if @preview_image
          @preview_image.path = @map_preview_path
        else
          _, _, width, height = @preview_bounds
          @preview_layer.append { @preview_image = @shoes.image(@map_preview_path, left: 0, top: 0, width: px(width), height: px(height)) }
        end
      end

      def shuffle_map
        config = room["config"].merge("seed" => SecureRandom.hex(4))
        action("configure", config: config)
      end

      def send_chat(field = @chat_field)
        text = field.text.strip
        return if text.empty?
        if action("chat", text: text)
          field.text = ""
        end
      end

      def copy_invite
        uri = URI.parse(@endpoint)
        address = if @hosting
          Socket.ip_address_list.find { |a| a.ipv4? && !a.ipv4_loopback? }&.ip_address || "YOUR-HOST"
        else
          uri.host
        end
        if uri.scheme == "tcp"
          text = "#{@endpoint} · Room #{room['code']}"
          notify("Copied the local room address. Use Host for friends for another computer.")
        else
          text = "burrow://#{address}:#{uri.port}/#{room['code']}"
          text += "?fingerprint=#{@fingerprint}" unless @fingerprint.to_s.empty?
          notify("Invite copied. Friends on the internet need your public hostname or IP.")
        end
        @shoes.clipboard = text
      end
    end
  end
end
