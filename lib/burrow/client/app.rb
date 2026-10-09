# frozen_string_literal: true

require "set"
require_relative "../mac_activity"
require_relative "theme"
require_relative "preferences"
require_relative "audio"
require_relative "diagnostics"
require_relative "connection"
require_relative "scene"
require_relative "screens"
require_relative "dialogs"
require_relative "match_ui"
require_relative "../server/reactor"
require_relative "../server/certificate"
require_relative "../server/process"

module Burrow
  module Client
    class App
      include Widgets
      include Screens
      include Dialogs
      include MatchUI
      attr_reader :state, :room, :page, :connection, :angle, :power, :target, :locked_target, :scene, :preferences, :selected_weapon

      def initialize(shoes, preferences: Preferences.new)
        @shoes, @preferences = shoes, preferences
        @activity = MacActivity.new("Burrow Brigade interactive match")
        @frame_log = Diagnostics::FrameLog.new
        @audio = Audio.new(preferences)
        @keys = Set.new
        @local_servers = {}
        @window_active = true
        @page = :menu
        @angle, @power, @fuse = -40.0, 0.65, 3
        @target = [900.0, 400.0]
        @selected_weapon = "rocket"
        @last_event, @last_turn = 0, nil
        @rooms, @rtt = [], 0
        @frame = 0
        build_root
        draw_page
        @shoes.keydown { |key| key_down(key) }
        @shoes.keyup { |key| key_up(key) }
        @shoes.activation do |active|
          @window_active = active
          update_activity
          cancel_controls unless active
        end
        @shoes.motion { |x, y| pointer(x, y) }
        @shoes.wheel do |delta, x, y|
          if @page == :match && !overlay? && Burrow.clock - (@zoom_at || 0) > 0.12
            sy = (y - @offset_y) / @scale - Scene::Y
            if sy.between?(0, 720) && delta != 0
              @scene.camera.zoom_by(delta > 0 ? 1 : -1)
              @zoom_at = Burrow.clock
            end
          end
        end
        @shoes.click { |button, x, y| pointer_click(button, x, y) }
        @shoes.release do |button, _x, _y|
          @camera_drag = nil if button == 2
          release_charge(source: :mouse) if button == 1 && @mouse_charge
        end
        @shoes.animate(60) { update }
        @shoes.finish { close }
        at_exit { close }
        if ENV["BURROW_CONNECT"]
          connect_to(ENV["BURROW_CONNECT"], name: ENV.fetch("BURROW_NAME", preferences["name"]), fingerprint: ENV["BURROW_FINGERPRINT"])
        elsif ENV["BURROW_AUTOPLAY"] == "1"
          play_local(quick: true)
        end
      end

      def play_event(event) = @audio.event(event)
      def motion? = preferences["motion"]
      def overlay? = !!@overlay
      def my_id = connection&.id
      def my_turn? = state && state["phase"] != "finished" && state["team"] == my_id && @connection_status == "online" && @scene && @scene.terrain_revision >= 0
      def room_host? = room && room["host_id"] == my_id
      def active_worm = state && state["worms"].find { |worm| worm["id"] == state["active"] }
      def my_inventory = state && state["teams"].find { |team| team["id"] == my_id }&.fetch("inventory")

      def update
        return if @closed
        started = Burrow.clock
        update_activity
        @frame += 1
        if [@shoes.width, @shoes.height] != @dimensions
          @resize_at ||= Burrow.clock
          if Burrow.clock - @resize_at > 0.12
            @resize_at = nil
            hide_overlay
            presentation = @scene.take_presentation if @page == :match && @scene
            scene&.close
            @scene = nil
            @canvas.remove
            build_root
            draw_page(presentation: presentation)
            @result_shown = false if @state && @state["phase"] == "finished"
          end
        end
        update_connection if connection
        update_map_preview if @page == :lobby
        if @page == :match
          update_controls
          @scene&.render
          if @scene&.finished_presented? && !@result_shown
            @result_shown = true
            show_result
          end
          refresh_match_hud if @frame % 6 == 0
        end
        if @toast_until && Burrow.clock > @toast_until
          @toast.clear
          @toast.hide
          @toast_until = nil
        end
        @audio.refresh if @frame % 120 == 0
      ensure
        @frame_log.record(started, page: @page, focused: @window_active, state: @state, scene: @scene, activity: @activity) if started
      end

      def action(type, **values)
        sent = connection&.send_action(type, **values)
        notify("Reconnecting. Your place in the room is saved.") unless sent
        sent
      end

      def connect_to(endpoint, name: preferences["name"], fingerprint: nil, pending: nil, session_key: nil, auto_start: false)
        name = Protocol.name(name)
        cancel_controls
        connection&.close
        @scene&.close
        @scene = @state = @room = nil
        @rooms = []
        @browser_signature = @lobby_signature = nil
        @result_shown = false
        hide_overlay
        @endpoint = endpoint
        @session_key = session_key
        @hosting = session_key == "hosted"
        @auto_start = auto_start
        @fingerprint = fingerprint || ""
        @pending = pending
        @connection = Connection.new(endpoint: endpoint, name: name,
          fingerprint: @fingerprint, token: preferences["sessions"][endpoint], allow_insecure: preferences["allow_lan"]).connect
        @connection_status = "connecting"
        preferences["name"] = name
        @page = :browser
        draw_page
      rescue RuleError, ArgumentError, SystemCallError => error
        notify(error.message)
      end

      def play_local(quick: false, hosting: false)
        entry = @local_servers[hosting]
        if entry && !entry[:server].running?
          entry[:server].stop
          @local_servers.delete(hosting)
          entry = nil
        end
        unless entry
          options = {host: hosting ? "0.0.0.0" : "127.0.0.1", port: hosting ? 4388 : 0,
            data_dir: File.join(Burrow.data_dir, hosting ? "host" : "local")}
          if hosting
            options[:certificate], options[:key] = Server::Certificate.ensure_pair(File.join(Burrow.data_dir, "host/tls"))
          end
          server = Server::ProcessHost.new(**options)
          entry = {server: server}
          @local_servers[hosting] = entry
        end
        @local_server = entry.fetch(:server)
        endpoint = "#{hosting ? 'tls' : 'tcp'}://127.0.0.1:#{@local_server.port}"
        # Ephemeral local ports change across launches; the identity key does not.
        session_key = hosting ? "hosted" : "local"
        token = preferences["sessions"][session_key]
        preferences["sessions"][endpoint] = token if token
        local_config = quick ? preferences["config"].merge("seed" => SecureRandom.hex(4)) : preferences["config"]
        connect_to(endpoint, fingerprint: @local_server.fingerprint, session_key: session_key, auto_start: quick,
          pending: {type: "create", name: "#{preferences['name']}'s brigade"[0, 24], bots: quick ? 2 : 1, config: local_config})
      rescue StandardError => error
        notify("Could not start the host: #{error.message}")
      end

      def notify(text)
        @last_notice = text.to_s
        return unless @toast
        @toast.clear do
          box(0, 0, 800, 42, color: Theme::INK, radius: 12)
          label(@last_notice, 20, 11, 760, size: 14, color: Theme::WHITE, align: "center")
        end
        @toast.show
        @toast_until = Burrow.clock + 5
      end

      def close
        return if @closed
        @closed = true
        @activity.close
        @connection&.close
        @local_servers.each_value { |entry| entry[:server].stop }
        @scene&.close
        @preview_art&.close
        @audio&.close
        @frame_log.write(activity: @activity)
      end

      def leave_room
        cancel_controls
        # Wait for the authoritative room-free snapshot before showing the
        # browser. Closing the connection sooner can discard a queued leave.
        hide_overlay if action("leave")
      end

      def to_menu
        cancel_controls
        @connection&.close
        @connection = nil
        @state = @room = nil
        @pending = nil
        @auto_start = false
        @scene&.close
        @scene = nil
        @page = :menu
        hide_overlay
        draw_page
      end

      private

      def update_activity
        @activity.active = !!(@window_active && @page == :match && @state && @state["phase"] != "finished")
      end

      def build_root
        @dimensions = [@shoes.width, @shoes.height]
        @scale = [@shoes.width / 1440.0, @shoes.height / 900.0].min
        @offset_x, @offset_y = (@shoes.width - px(1440)) / 2, (@shoes.height - px(900)) / 2
        @canvas = @shoes.stack(left: @offset_x, top: @offset_y, width: px(1440), height: px(900)) do
          @content = @shoes.stack(left: 0, top: 0, width: px(1440), height: px(900)) {}
          @modal = @shoes.stack(left: 0, top: 0, width: px(1440), height: px(900)) {}
          @modal.hide
          @toast = @shoes.stack(left: px(320), top: px(774), width: px(800), height: px(42)) {}
          @toast.hide
        end
      end

      def draw_page(presentation: nil)
        if @page != :lobby && @preview_art
          @preview_art.close
          @preview_art = @map_preview_signature = @map_preview_path = nil
        end
        @content.clear do
          case @page
          when :menu then draw_menu
          when :browser then draw_browser
          when :lobby then draw_lobby
          when :match then draw_match(presentation: presentation)
          end
        end
      end

      def update_connection
        update = connection.poll
        old_status = @connection_status
        @connection_status, @status_message, @rtt = update.values_at(:status, :message, :rtt)
        if update[:welcome]
          sessions = preferences["sessions"].dup
          sessions[@endpoint] = update[:welcome]["token"]
          sessions[@session_key] = update[:welcome]["token"] if @session_key
          preferences["sessions"] = sessions
        end
        update[:notices].each { |message| notify(message) }
        if (packet = update[:state])
          @pending_action = nil if @pending_action && packet.fetch("ack", 0) >= @pending_action
          old_room = @room
          @room, @state = packet.values_at("room", "match")
          @rooms = packet["rooms"] if packet["rooms"]
          next_page = @state ? :match : @room ? :lobby : :browser
          new_match = @state && @room["match_id"] != old_room&.fetch("match_id", nil)
          if next_page != @page || new_match
            @lobby_signature = @browser_signature = nil
            if @page == :lobby
              @preview_art&.close
              @preview_art = @map_preview_signature = @map_preview_path = nil
            end
            @scene&.close
            @scene = nil
            @last_event, @last_turn = 0, nil if next_page == :match
            @result_shown = false
            hide_overlay
            @page = next_page
            draw_page
          elsif @page == :lobby
            signature = @room.slice("members", "host_id", "config", "name")
            if signature != @lobby_signature
              @lobby_signature = Marshal.load(Marshal.dump(signature))
              draw_page
            end
            set_text(@chat_history, @room["messages"].last(7).map { |m| "#{m['name']}: #{m['text']}" }.join("\n"))
          elsif @page == :browser && @browser_signature != @rooms
            @browser_signature = @rooms
            draw_page
          end
          if @page == :match
            @scene.accept(@state)
            if @state["turn"] != @last_turn
              @last_turn = @state["turn"]
              cancel_controls(stop: false)
              @pending_action = @locked_target = nil
              @selected_weapon = (["rocket", "grenade"] + Catalog::WEAPONS.keys).find do |id|
                (my_inventory || {}).fetch(id, 0) != 0 &&
                  !(state.dig("config", "terrain") == "cavern" && Catalog::SKY.include?(Catalog.fetch(id)[:kind]))
              end || "skip"
              @angle = active_worm["facing"] < 0 ? -140 : -40
              @target = [active_worm["x"] + active_worm["facing"] * 180, active_worm["y"] - 140]
            end
            if @state["phase"] != "finished"
              @result_shown = false
            end
          end
          if @pending && @connection_status == "online"
            pending = @pending
            @pending = nil
            # A recovered session resumes its current room, preserving an unfinished game.
            action(pending.delete(:type), **pending) unless @room
          end
          if @auto_start && @room && !@state && room_host? && @room["members"].length >= 2
            @auto_start = false
            action("start")
          end
        end
        if old_status != @connection_status
          draw_page if @page == :browser
          set_text(@connection_label, @connection_status == "online" ? "Connected · #{@endpoint}" : @status_message)
          notify(@status_message) if %w[rejected reconnecting].include?(@connection_status)
          cancel_controls(stop: false) unless @connection_status == "online"
          @pending_action = nil unless @connection_status == "online"
        end
      rescue SystemCallError => error
        notify("Could not save your preferences: #{error.class}")
      end
    end
  end
end
