# frozen_string_literal: true

module Burrow
  module Client
    module Screens
      def draw_menu
        box(0, 0, 1440, 900, color: Theme::PAPER, radius: 0)
        image("menu-bg", 0, 0, 1440, 900)
        micro("A LITTLE FRIENDLY DESTRUCTION", 72, 55, 450, color: Theme::TEAL)
        button("Settings", 1240, 40, 130) { show_settings }
        label("BURROW", 66, 155, 640, size: 90, font: Theme.display, weight: 650)
        label("BRIGADE", 66, 259, 670, size: 90, font: Theme.display, weight: 650)
        label("Tiny teams. Enormous trouble.", 76, 388, 600, size: 25, font: Theme.display)
        label("Gather your crew, pick something ridiculous,\nand leave the landscape a little different.", 78, 440, 470,
          size: 17, color: Theme::MUTED)
        button("Quick battle", 78, 530, 310, primary: true) { play_local(quick: true) }
        button("Create a match", 78, 582, 310) { play_local }
        button("Play with friends", 78, 634, 310) { show_connect }
        button("The arsenal", 78, 711, 148, height: 32) { show_arsenal(browse: true) }
        button("How to play", 240, 711, 148, height: 32) { show_guide }
        line(78, 792, 452, 792)
        micro("6 TEAMS  /  48 TOYS  /  ENDLESS ISLANDS", 78, 812, 500)
        micro("BURROW BRIGADE  #{VERSION}", 78, 865, 420)
        label("Hello, #{preferences['name']}.", 1140, 854, 230, size: 14, align: "right", color: Theme::MUTED)
      end

      def page_header(title, subtitle, back: true)
        box(0, 0, 1440, 900, color: Theme::PAPER, radius: 0)
        micro("BURROW BRIGADE", 48, 34, 400, color: Theme::TEAL)
        label(title, 48, 65, 1020, size: 38, font: Theme.display)
        label(subtitle, 50, 120, 1190, size: 15, color: Theme::MUTED)
        button("Main menu", 1220, 48, 166) { to_menu } if back
      end

      def draw_browser
        page_header("Find your kind of trouble", "Join a room on this server, or make one for your friends.")
        @connection_label = label(@connection_status == "online" ? "Connected · #{@endpoint}" : @status_message || "Connecting…", 50, 164, 1160, size: 13, color: Theme::TEAL)
        button("Create room", 1132, 157, 252, primary: true) { show_create_room }
        button("Join with a code", 1132, 207, 252) { show_join_code }
        if @connection_status == "rejected"
          label("Connection needs attention", 60, 310, 700, size: 28, font: Theme.display)
          label(@status_message, 60, 364, 820, size: 17, color: Theme::MUTED)
          button("Connect as a new player", 60, 430, 280) do
            preferences["sessions"].delete(@endpoint)
            preferences["sessions"].delete(@session_key) if @session_key
            preferences.save
            connect_to(@endpoint, fingerprint: @fingerprint, pending: @pending,
              session_key: @session_key, auto_start: @auto_start)
          end
        elsif @rooms.empty?
          grub(1, 608, 310, size: 180)
          label("An island to yourselves", 395, 525, 650, size: 32, font: Theme.display, align: "center")
          label("No rooms here yet. Create one, then share the invite\nwith up to five friends. Computer teams can fill the gaps.", 360, 582, 720, size: 17, color: Theme::MUTED, align: "center")
        else
          @rooms.first(8).each_with_index do |entry, i|
            y = 254 + i * 66
            line(50, y + 58, 1060, y + 58)
            label(entry["name"], 66, y + 4, 420, size: 19, font: Theme.display)
            label("#{entry['biome'].capitalize} · #{entry['count']}/6 teams · #{entry['locked'] ? 'Private' : 'Open'}", 66, y + 31, 600, size: 13, color: Theme::MUTED)
            label(entry["stage"] == "lobby" ? "In the lobby" : "In battle", 680, y + 17, 150, size: 14, color: Theme::TEAL)
            control = button("Join #{entry['code']}", 840, y + 10, 204) do
              if entry["locked"]
                show_join_code(entry["code"])
              else
                action("join", code: entry["code"])
              end
            end
            control.state = "disabled" unless entry["stage"] == "lobby" && entry["count"] < 6
          end
        end
        micro("PRIVATE HOSTING · NO ACCOUNT REQUIRED", 50, 844, 620)
        button("Change server", 1132, 834, 252) { show_connect }
      end

      def draw_lobby
        page_header(room["name"], "A little preparation. A lot of consequences.", back: false)
        button("Leave room", 1220, 44, 168) { leave_room }
        micro("YOUR CREW", 48, 190, 350)
        label("#{room['members'].length} / 6 teams", 48, 218, 370, size: 28, font: Theme.display)
        6.times do |i|
          y = 270 + i * 67
          member = room["members"][i]
          if member
            grub(i, 44, y - 3, size: 59)
            label(member["name"], 118, y + 4, 246, size: 18, font: Theme.display)
            detail = member["bot"] ? "Computer" : member["id"] == my_id ? "You" : "Friend"
            detail += " · Host" if member["id"] == room["host_id"]
            detail += member["connected"] ? (member["ready"] || member["id"] == room["host_id"] ? " · Ready" : " · Getting ready") : " · Reconnecting"
            label(detail, 120, y + 31, 300, size: 12, color: Theme::MUTED)
            if room_host? && member["id"] != my_id
              button("Remove", 395, y + 12, 88, height: 32) { action("kick", player: member["id"]) }
            end
          else
            box(55, y + 8, 38, 38, color: Theme::WELL, radius: 19)
            label("+", 58, y + 11, 32, size: 22, color: Theme::MUTED, align: "center")
            label("An open spot", 118, y + 10, 230, size: 16, color: Theme::MUTED)
            button("Add computer", 334, y + 6, 150, height: 32) { action("add_bot") } if room_host?
          end
          line(55, y + 60, 486, y + 60) unless i == 5
        end
        line(520, 190, 520, 692)
        micro("THE BATTLEFIELD", 556, 190, 500)
        label(room.dig("config", "biome").capitalize + " islands", 556, 218, 600, size: 28, font: Theme.display)
        button("Shuffle map", 1190, 218, 196, height: 32) { shuffle_map } if room_host?
        draw_map_preview(room["config"], 556, 274, 830, 350)
        config = room["config"]
        label("#{config['worms']} grubs each", 566, 654, 240, size: 17, font: Theme.display)
        label("#{config['health']} health", 824, 654, 240, size: 17, font: Theme.display)
        label("#{config['turn_seconds']} seconds / turn", 1090, 654, 296, size: 17, font: Theme.display)
        label("#{config['scheme'].capitalize} arsenal · #{config['terrain'].capitalize} · Seed: #{config['seed']}", 566, 688, 810, size: 13, color: Theme::MUTED)
        button("Match rules", 1190, 734, 196) { show_rules(readonly: !room_host?) }
        button("Copy invite", 970, 734, 196) { copy_invite }
        label("ROOM #{room['code']}", 556, 738, 390, size: 19, font: Theme.mono, color: Theme::TEAL)
        line(48, 786, 1386, 786)
        @chat_history = label(room["messages"].last(7).map { |m| "#{m['name']}: #{m['text']}" }.join("\n"), 58, 696, 450, size: 12, color: Theme::MUTED)
        @chat_field = input("", 56, 811, 364)
        @chat_field.finish = proc { send_chat }
        button("Send", 432, 811, 88) { send_chat }
        if room_host?
          start = button("Start the mischief", 1034, 814, 352, primary: true) { action("start") }
          start.state = "disabled" if room["members"].length < 2 || room["members"].any? { |m| !m["bot"] && m["id"] != my_id && (!m["ready"] || !m["connected"]) }
          label("Friends choose Ready when they're set.", 566, 823, 438, size: 13, color: Theme::MUTED)
        else
          me = room["members"].find { |m| m["id"] == my_id }
          button(me && me["ready"] ? "Not ready yet" : "Ready to rumble", 1034, 814, 352, primary: true) { action("ready", ready: !me["ready"]) }
          label("The host will start when everyone is ready.", 566, 823, 438, size: 13, color: Theme::MUTED)
        end
      end

      def draw_map_preview(config, x, y, width, height)
        image("sky-#{config['biome']}", x, y, width, height)
        dimensions = Config.new(config).world_size(room["members"].length)
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
        if @map_preview_path
          @preview_layer.append { @preview_image = @shoes.image(@map_preview_path, left: 0, top: 0, width: px(width), height: px(height)) }
        end
        water = (dimensions[1] - 96).fdiv(dimensions[1])
        box(x, y + height * water, width, height * (1 - water), color: "#438c97dd", radius: 0)
        micro("#{dimensions[0]} × #{dimensions[1]} · #{config.fetch('map_size', 'auto').capitalize} battlefield", x + 12, y + 12, width - 24)
      end

      def update_map_preview
        return unless @preview_art && (result = @preview_art.poll)
        @map_preview_path = result[:overview]
        return unless @preview_layer
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

      def send_chat
        text = @chat_field.text.strip
        return if text.empty?
        if action("chat", text: text)
          @chat_field.text = ""
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
