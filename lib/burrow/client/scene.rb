# frozen_string_literal: true

require_relative "terrain_art"
require_relative "camera"
require_relative "timeline"

module Burrow
  module Client
    class Scene
      include Widgets
      Y = 104
      FX = JSON.parse(File.read(File.join(Theme::ART, "manifest.json"), encoding: Encoding::UTF_8)).fetch("extras").fetch("fx_animations").freeze
      attr_reader :terrain_revision, :terrain_packet, :actors, :frame_count, :max_frame_ms, :last_frame_ms, :camera, :timeline, :positions

      # Inspection tools can request the full collision grid. Normal rendering
      # forwards its compressed packet to the worker without decoding/hashing it
      # on the GUI thread, including on resize and every explosion.
      def terrain = (@terrain ||= Terrain.restore(@terrain_packet) if @terrain_packet)

      def initialize(shoes, controller, scale: 1, presentation: nil)
        @shoes, @controller, @scale = shoes, controller, scale
        @actors, @projectile_nodes, @hazard_nodes, @frame_cache, @hurt_until = {}, {}, {}, {}, {}
        @effects = []
        @frame_count, @max_frame_ms = 0, 0.0
        @frame_times = []
        @terrain_art = presentation ? presentation.fetch(:terrain_art) : TerrainArt.new
        @terrain_revision = -1
        @ui_scale = scale
        @timeline = presentation ? presentation.fetch(:timeline) : Timeline.new
        if presentation
          @camera = presentation[:camera]
          @terrain_packet = presentation[:terrain_packet]
          @restored_terrain_result = presentation[:terrain_result]
          @last_turn, @finished_at = presentation.values_at(:last_turn, :finished_at)
          @hurt_until = presentation[:hurt_until]
        end
        @tiles = {}
        @slot = @shoes.stack(left: 0, top: px(Y), width: px(1440), height: px(720)) do
          @backdrop = image("sky-meadow", 0, 0, 1440, 720)
        end
      end

      def build_world(state)
        @width = state.fetch("world_width", WIDTH)
        @height = state.fetch("world_height", HEIGHT)
        unless @camera
          @camera = Camera.new(@width, @height)
          @camera.follow
        end
        @slot.append do
          @world = @shoes.stack(left: 0, top: 0, width: px(@width)) do
            @terrain_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @props_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @actor_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @shot_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @water = box(0, @height - 96, @width, 96, color: "#438c97dd", radius: 0)
            @waterline = line(0, @height - 96, @width, @height - 96, color: "#c1e9dd", width: 3)
            @effect_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @aim_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) do
              @aim_dots = Array.new(15) { @shoes.oval(0, 0, px(4), fill: "#fffaf0cc", stroke: "#182d3566", strokewidth: px(1)) }
              @reticle = @shoes.oval(0, 0, px(24), fill: "#ffffff00", stroke: Theme::INK, strokewidth: px(1.5))
              @lock_marker = label("⊕", 0, 0, 38, size: 31, color: Theme::ORANGE, align: "center")
              @lock_caption = label("LOCKED", 0, 0, 72, size: 10, color: Theme::INK, font: Theme.mono, align: "center")
              @placement = box(0, 0, 140, 12, color: "#edc16d88", radius: 2, stroke: Theme::WHITE)
              @held_weapon = image("weapons/rocket", 0, 0, 30, 30)
              @active_arrow = label("▼", 0, 0, 30, size: 22, color: Theme::ORANGE, align: "center")
              @rope_line = line(0, 0, 0, 0, color: "#eac386", width: 2)
              @rope_line.hide unless @rope_line.hidden
            end
            @cache = @shoes.stack(left: 0, top: 0, width: 1, height: 1) {}
            @cache.hide
          end
          button("−", 20, 16, 36, height: 30) { camera.zoom_by(-1) }
          button("+", 62, 16, 36, height: 30) { camera.zoom_by(1) }
          button("Map · G", 104, 16, 112, height: 30) { toggle_map }
          button("Follow · F", 222, 16, 112, height: 30) { camera.follow }
          @camera_caption = micro("", 20, 56, 470)
          @map_y, @map_h = 572, 128
          box(1112, @map_y - 12, 308, @map_h + 22, color: "#182d35df", radius: 12)
          @minimap_layer = @shoes.stack(left: 0, top: 0, width: px(1440), height: px(720)) {}
          @minimap = nil
          @map_marks = {}
          @map_frame = box(1122, @map_y, 286, @map_h, color: "#ffffff00", radius: 0, stroke: "#fffaf0")
          @loading_label = label("Charting the battlefield…", 400, 310, 640, size: 24, font: Theme.display, align: "center")
        end
      end

      def accept(state)
        build_world(state) unless @world
        @latest = state
        @timeline.accept(state)
        if @biome != state.dig("config", "biome")
          @biome = state.dig("config", "biome")
          @backdrop.path = File.join(Theme::ART, "sky-#{@biome}.png")
        end
        if state["terrain"] && (!@terrain_packet || @terrain_packet["revision"] != state["terrain_revision"])
          @terrain = nil
          @terrain_packet = state["terrain"]
          @terrain_art.request(@terrain_packet, @biome)
        end
      end

      def render
        return unless @latest
        started = Burrow.clock
        @frame_count += 1
        @state = @timeline.sample(now: started)
        @scale = @ui_scale * camera.zoom
        if @last_turn != @state["turn"]
          @last_turn = @state["turn"]
          camera.follow if @frame_count > 1 && !camera.overview?
        end
        active = @state["worms"].find { |w| w["id"] == @state["active"] }
        focus = @state["projectiles"].first || active
        camera.update(focus&.values_at("x", "y"), dt: started - (@last_render || started))
        @last_render = started
        origin = [px(-camera.x), px(-camera.y)]
        @world.move(*origin) if origin != @origin
        @origin = origin
        resize_world if @world_scale != @scale
        update_terrain if @terrain_art
        if @terrain_art.error && !@render_error_shown
          @render_error_shown = true
          @controller.notify("The landscape renderer stopped: #{@terrain_art.error}")
        end
        reconcile_actors
        reconcile_objects(@projectile_nodes, @state["projectiles"], @shot_layer, projectile: true)
        reconcile_objects(@hazard_nodes, @state["hazards"], @props_layer, projectile: false)
        @timeline.events.each { |e| event(e); @controller.play_event(e) }
        @finished_at ||= started if @state["phase"] == "finished" && @timeline.tick >= @state["tick"]
        dense = @state["worms"].count { |w| w["hp"] > 0 } > 18 || camera.zoom < 0.7
        @positions = {}
        @state["worms"].each do |worm|
          node = @actors.fetch(worm["id"])
          if worm["hp"] <= 0
            node[:dead_since] ||= started
            if started - node[:dead_since] > 0.8
              node[:slot].hide
              next
            end
          end
          x, y = worm.values_at("x", "y")
          @positions[worm["id"]] = [x, y]
          sx, sy = camera.screen(x, y)
          visible = sx.between?(-90, 1530) && sy.between?(-90, 810)
          if node[:visible] != visible
            visible ? node[:slot].show : node[:slot].hide
            node[:visible] = visible
          end
          next unless visible
          resize_actor(node) if node[:scale] != @scale
          position = [px(x - 42), px(y - 68)]
          node[:slot].move(*position) if node[:position] != position
          node[:position] = position
          state = if worm["hp"] <= 0
            "dead"
          elsif @state["phase"] == "finished" && worm["team"] == @state["winner"]
            "victory"
          elsif @hurt_until.fetch(worm["id"], 0) > started
            "hurt"
          elsif worm["vy"].abs > 15
            "jump"
          elsif worm["vx"].abs > 8
            "walk"
          else
            "idle"
          end
          count, fps = {"idle" => [4, 6], "walk" => [8, 12], "jump" => [4, 8], "hurt" => [3, 9], "victory" => [6, 8], "dead" => [1, 1]}.fetch(state)
          frame = if !@controller.motion?
            0
          elsif state == "hurt"
            [((started - (@hurt_until[worm["id"]] - 0.35)) * fps).floor, 2].min.clamp(0, 2)
          elsif state == "jump"
            worm["vy"] < -30 ? 1 : worm["vy"] > 30 ? 3 : 2
          else
            (started * fps).to_i % count
          end
          path = "grubs/#{worm['facing'] < 0 ? 'left/' : ''}#{node[:team]}-#{state}-#{frame}"
          cache_frame(path)
          node[:image].path = File.join(Theme::ART, path + ".png") if node[:path] != path
          node[:path] = path
          tx, ty = @controller.target
          compact = dense && worm["id"] != @state["active"] && Math.hypot(tx - x, ty - y + 15) > 24
          if node[:compact] != compact
            node[:badge].style(left: px(compact ? 26 : 0), top: px(compact ? 12 : 0), width: px(compact ? 32 : 84), height: px(compact ? 17 : 20))
            node[:label].style(left: px(compact ? 27 : 1), top: px(compact ? 13 : 2), width: px(compact ? 30 : 82))
            node[:compact] = compact
          end
          set_text(node[:label], compact ? worm['hp'].to_s : "#{worm['name']}  #{worm['hp']}")
          badge_color = worm["frozen"] ? "#d6eaf1" : worm["shield"] ? "#b9dcb6" : Theme::INK
          node[:badge].style(fill: badge_color) if node[:badge_color] != badge_color
          node[:badge_color] = badge_color
          if worm["hp"] <= 0 && !node[:health_hidden]
            node[:label].hide
            node[:badge].hide
            node[:health_hidden] = true
          end
        end
        @state["projectiles"].each do |p|
          node = @projectile_nodes[p["id"]]
          x, y = p.values_at("x", "y")
          node[:image].style(left: px(x - 14), top: px(y - 14), width: px(28), height: px(28))
          node[:image].rotate((Math.atan2(p["vy"], p["vx"]) * 180 / Math::PI / 6).round * 6) unless p["walker"]
          if node[:fuse]
            node[:fuse].style(left: px(x - 14), top: px(y - 35), width: px(28), size: [px(12), 8].max)
            set_text(node[:fuse], p["life"] ? "#{(p['life'].fdiv(TICK_RATE)).ceil}s" : "")
          end
          if @controller.motion? && @frame_count % 4 == 0 && !p["walker"] && Math.hypot(p["vx"], p["vy"]) > 40
            add_particle(x, y, color: "#ffefc188", life: 0.35, size: 7, vx: 0, vy: -8)
          end
        end
        @state["hazards"].each do |h|
          node = @hazard_nodes[h["id"]]
          if %w[gas fire].include?(h["kind"])
            radius = h["radius"]
            node[:image].style(left: px(h["x"] - radius), top: px(h["y"] - radius), width: px(radius * 2), height: px(radius * 2))
          else
            node[:image].style(left: px(h["x"] - 16), top: px(h["y"] - 29), width: px(32), height: px(32))
          end
        end
        render_aim(started)
        render_effects(started)
        if @water_level != @state["water"] || @water_scale != @scale
          @water.style(top: px(@state["water"]), width: px(@width), height: px(@height - @state["water"]))
          @waterline.style(top: px(@state["water"]), x2: px(@width), y2: px(@state["water"]))
          @water_level, @water_scale = @state["water"], @scale
        end
        render_navigation
        elapsed = (Burrow.clock - started) * 1000
        @last_frame_ms = elapsed
        @frame_times << elapsed
        @frame_times.shift if @frame_times.length > 600
        @max_frame_ms = [@max_frame_ms, elapsed].max
      end

      def performance
        sorted = @frame_times.sort
        {frames: frame_count, mean_ruby_scene_ms: sorted.empty? ? 0 : sorted.sum / sorted.length,
          p95_ruby_scene_ms: sorted.empty? ? 0 : sorted[(sorted.length * 0.95).floor], max_ruby_scene_ms: max_frame_ms}
      end

      def event(event)
        now = Burrow.clock
        x, y = event.values_at("x", "y")
        if event["kind"] == "damage"
          @hurt_until[event["worm"]] = now + 0.35
          float_text("−#{event['amount']}", x, y, "#a8462a")
        elsif event["kind"] == "heal"
          float_text("+#{event['amount']}", x, y, "#2e745a")
          sprite_effect("sparkle", x, y, 1.3)
        elsif event["kind"] == "pickup"
          float_text(event["text"], x, y - 15, Theme::TEAL)
          sprite_effect("sparkle", x, y - 15, 1.2)
        elsif event["kind"] == "jump"
          sprite_effect("dust", x, y, 0.8)
        elsif event["kind"] == "activate"
          sprite_effect(event["stage"] == "flying" ? "smoke" : "dust", x, y, 0.6)
        elsif event["kind"] == "defeat"
          sprite_effect("smoke", x, y - 10, 1.1)
        elsif event["kind"] == "melee"
          sprite_effect("sparkle", x + event.fetch("facing", 1) * 25, y, 1.3)
        elsif %w[explosion splash teleport dig].include?(event["kind"])
          fx = {"explosion" => "explosion", "splash" => "splash", "teleport" => "sparkle", "dig" => "dust"}.fetch(event["kind"])
          scale = fx == "explosion" ? (event.fetch("radius", 45) / 50.0).clamp(0.5, 2.6) : 1.0
          sprite_effect(fx, x, y, scale)
          sprite_effect("sparkle", event["x2"], event["y2"], 1.3) if event["kind"] == "teleport" && event["x2"]
          color = event["kind"] == "splash" ? "#a3e2e6" : event["kind"] == "teleport" ? "#a68dcc" : "#f6bc65"
          count = @controller.motion? ? (event["kind"] == "explosion" ? 18 : 8) : 3
          count.times do |i|
            angle = i * Math::PI * 2 / count
            speed = 40 + i % 5 * 30
            add_particle(x, y, color: i.even? ? color : "#fff1c5", size: 4 + i % 5 * 2,
              life: 0.35 + i % 4 * 0.12, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - 50)
          end
          if event["kind"] == "explosion"
            @effect_layer.append do
              ring = @shoes.oval(px(x - 8), px(y - 8), px(16), fill: "#fff3ca00", stroke: "#fff2c9", strokewidth: px(5))
              retain_effect(node: ring, born: now, life: 0.4, kind: :ring, x: x, y: y, radius: event["radius"])
            end
          end
        elsif event["kind"] == "beam"
          sprite_effect("sparkle", x, y, 0.45)
          @effect_layer.append do
            node = line(x, y, event["x2"], event["y2"], color: event["style"] == "laser" ? "#fa7660" : "#fff1b5", width: event["style"] == "laser" ? 4 : 2)
            retain_effect(node: node, born: now, life: 0.15, kind: :line)
          end
        end
      end

      def finished_presented? = @finished_at && Burrow.clock - @finished_at > 0.8

      def toggle_map
        camera.overview? ? camera.follow : camera.overview
      end

      def navigation_hit?(x, y)
        (x.between?(12, 340) && y.between?(10, 68)) ||
          (x.between?(16, 1066) && y.between?(686, 714)) ||
          (x.between?(1112, 1420) && y.between?(@map_y - 12, @map_y + @map_h + 10))
      end

      def navigate(x, y)
        return false unless x.between?(1122, 1408) && y.between?(@map_y, @map_y + @map_h)
        camera.navigate((x - 1122) / 286.0 * @width, (y - @map_y) / @map_h.to_f * @height)
        true
      end

      def close
        @terrain_art&.close
        @terrain_art = nil
      end

      # Transfer non-visual state when the window's UI is rebuilt. Keeping the
      # worker's textures avoids a blank world and an expensive rerasterization;
      # keeping the timeline prevents replaying shots/sounds during a resize.
      def take_presentation
        saved = {terrain_art: @terrain_art, terrain_packet: @terrain_packet,
          terrain_result: @terrain_result || @restored_terrain_result,
          camera: camera, timeline: timeline, last_turn: @last_turn,
          finished_at: @finished_at, hurt_until: @hurt_until}
        @terrain_art = nil
        saved
      end

      private

      def resize_world
        @world_scale = @scale
        [@world, @terrain_layer, @props_layer, @actor_layer, @shot_layer, @effect_layer, @aim_layer].each { |layer| layer.style(width: px(@width)) }
        @tiles.each_value { |tile| place_tile(tile) }
        @aim_dots.each { |dot| dot.style(width: px(4), height: px(4), strokewidth: [px(1), 1].max) }
        @reticle.style(width: px(24), height: px(24))
        @lock_marker.style(width: px(38), size: [px(31), 12].max)
        @lock_caption.style(width: px(72), size: [px(10), 7].max)
        @active_arrow.style(width: px(30), size: [px(22), 10].max)
        @effects.each { |effect| effect[:node].remove }
        @effects.clear
      end

      def resize_actor(node)
        node[:scale], node[:compact] = @scale, nil
        node[:slot].style(width: px(84), height: px(78))
        node[:image].style(left: px(16), top: px(24), width: px(52), height: px(52))
        node[:label].style(size: [px(11), 6].max)
      end

      def place_tile(tile)
        tile[:node].style(left: px(tile[:x]), top: px(tile[:y]), width: px(tile[:x] + tile[:width]) - px(tile[:x]), height: px(tile[:y] + tile[:height]) - px(tile[:y]))
      end

      def update_terrain
        return unless (result = @terrain_art.poll || @restored_terrain_result)
        @restored_terrain_result = nil
        @terrain_result = result
        result[:tiles].each do |spec|
          # Worker results contain only serializable texture metadata, never UI
          # nodes from the previous window layout.
          tile = spec.dup
          if (existing = @tiles[tile[:id]])
            existing[:node].path = tile[:path] if existing[:path] != tile[:path]
            existing[:path] = tile[:path]
          else
            @terrain_layer.append do
              tile[:node] = @shoes.image(tile[:path], left: px(tile[:x]), top: px(tile[:y]), width: px(tile[:x] + tile[:width]) - px(tile[:x]), height: px(tile[:y] + tile[:height]) - px(tile[:y]), alt: "Destructible landscape")
            end
            @tiles[tile[:id]] = tile
          end
        end
        saved, @scale = @scale, @ui_scale
        if @minimap
          @minimap.path = result[:overview]
        else
          @minimap_layer.append do
            @minimap = @shoes.image(result[:overview], left: px(1122), top: px(@map_y), width: px(286), height: px(@map_h))
          end
        end
        @scale = saved
        @terrain_revision = result[:revision]
        @loading_label.hide unless @loading_label.hidden
      end

      def render_navigation
        saved, @scale = @scale, @ui_scale
        set_text(@camera_caption, "#{(camera.zoom * 100).round}% · #{camera.following ? 'Following the action' : 'Free camera'} · Middle-drag to pan")
        @state["worms"].each do |w|
          unless @map_marks[w["id"]]
            @slot.append { @map_marks[w["id"]] = box(0, 0, 5, 5, color: COLORS[@state["teams"].find { |t| t["id"] == w["team"] }["color"]], radius: 2) }
          end
          dot = @map_marks[w["id"]]
          if w["hp"] <= 0
            dot.hide unless dot.hidden
          else
            dot.move(px(1122 + w["x"] / @width * 286 - 2), px(@map_y + w["y"] / @height * @map_h - 2))
          end
        end
        left, top = [camera.x, 0].max, [camera.y, 0].max
        right, bottom = [camera.x + 1440 / camera.zoom, @width].min, [camera.y + 720 / camera.zoom, @height].min
        @map_frame.style(left: px(1122 + left / @width * 286), top: px(@map_y + top / @height * @map_h),
          width: px((right - left) / @width * 286), height: px((bottom - top) / @height * @map_h))
        @scale = saved
      end

      def cache_frame(path)
        return if @frame_cache[path]
        @cache.append { @frame_cache[path] = image(path, 0, 0, 1, 1) }
      end

      def reconcile_actors
        @state["worms"].each do |w|
          next if @actors[w["id"]]
          color = @state["teams"].find { |t| t["id"] == w["team"] }["color"]
          node = {team: color}
          @actor_layer.append do
            node[:slot] = @shoes.stack(left: 0, top: 0, width: px(84), height: px(78)) do
              node[:badge] = box(0, 0, 84, 20, color: Theme::INK, radius: 6)
              node[:label] = label("#{w['name']}  #{w['hp']}", 1, 2, 82, size: 11, color: COLORS[color], align: "center")
              node[:image] = image("grubs/#{color}-idle-0", 16, 24, 52, 52)
            end
          end
          @actors[w["id"]] = node
        end
      end

      def reconcile_objects(nodes, objects, layer, projectile:)
        ids = objects.map { |p| p["id"] }
        (nodes.keys - ids).each do |id|
          node = nodes.delete(id)
          node[:image].remove
          node[:fuse]&.remove
        end
        objects.each do |p|
          next if nodes[p["id"]]
          layer.append do
            kind = p["kind"]
            picture = if projectile
              image("weapons/#{p['weapon']}", p["x"] - 14, p["y"] - 14, 28, 28)
            elsif %w[fire gas].include?(kind)
              @shoes.oval(px(p["x"] - p["radius"]), px(p["y"] - p["radius"]), px(p["radius"] * 2),
                fill: kind == "gas" ? "#a3b56366" : "#f57c4966", strokewidth: 0)
            else
              art = {"crate" => "crate", "mine" => "mine-prop", "barrel" => "barrel-prop"}.fetch(kind, "weapons/#{kind}")
              image(art, p["x"] - 16, p["y"] - 29, 32, 32)
            end
            nodes[p["id"]] = {image: picture}
            if projectile && p["fused"]
              nodes[p["id"]][:fuse] = label("", p["x"] - 14, p["y"] - 35, 28, size: 12, color: Theme::INK, font: Theme.mono, align: "center")
            end
          end
        end
      end

      def render_aim(now)
        active = @state["worms"].find { |w| w["id"] == @state["active"] }
        position = active && @positions[active["id"]]
        unless position
          @aim_layer.hide unless @aim_layer.hidden
          return
        end
        x, y = position
        if @state["phase"] == "finished" || active["hp"] <= 0
          @aim_layer.hide unless @aim_layer.hidden
          return
        end
        @aim_layer.show if @aim_layer.hidden
        @active_arrow.move(px(x - 15), px(y - 101 + (@controller.motion? ? Math.sin(now * 5) * 3 : 0)))
        can_aim = @controller.my_turn? && @state["phase"] == "aiming" && !@controller.overlay?
        weapon = Catalog.fetch(@controller.selected_weapon)
        aimed = can_aim && Catalog::AIMED.include?(weapon[:kind]) && !@controller.special_control
        angle = @controller.angle * Math::PI / 180
        speed = weapon[:id] == "mortar" ? 580 : 130 + @controller.power * 540
        ballistic = Catalog::CHARGED.include?(weapon[:kind])
        @aim_dots.each_with_index do |dot, i|
          if aimed
            distance = 26 + i * 10
            t = (distance - 20) / speed
            gravity = 285 * @state.dig("config", "gravity") * (@state.dig("effects", "low_gravity") ? 0.45 : 1)
            drift = ballistic && %w[rocket homing].include?(weapon[:id]) ? @state["wind"] * 21 * t * t : 0
            fall = ballistic ? 0.5 * gravity * t * t : 0
            dot.move(px(x + Math.cos(angle) * distance + drift - 2), px(y - 13 + Math.sin(angle) * distance + fall - 2))
            dot.show if dot.hidden
          else
            dot.hide unless dot.hidden
          end
        end
        targeted = can_aim && Catalog::TARGETED.include?(weapon[:kind]) && !@controller.special_control
        if targeted
          tx, ty = @controller.target
          @reticle.move(px(tx - 12), px(ty - 12))
          @reticle.show if @reticle.hidden
        else
          @reticle.hide unless @reticle.hidden
        end
        if can_aim && weapon[:id] == "homing" && @controller.locked_target
          tx, ty = @controller.locked_target
          @lock_marker.move(px(tx - 19), px(ty - 23))
          @lock_caption.move(px(tx - 36), px(ty + 17))
          @lock_marker.show if @lock_marker.hidden
          @lock_caption.show if @lock_caption.hidden
        else
          @lock_marker.hide unless @lock_marker.hidden
          @lock_caption.hide unless @lock_caption.hidden
        end
        if targeted && weapon[:kind] == "girder"
          tx, ty = @controller.target
          @placement.style(left: px(tx - 70), top: px(ty), width: px(140), height: px(12))
          @placement.show if @placement.hidden
        else
          @placement.hide unless @placement.hidden
        end
        if can_aim && !@controller.special_control
          path = File.join(Theme::ART, "weapons/#{weapon[:id]}.png")
          @held_weapon.path = path if @held_weapon.path != path
          @held_weapon.style(left: px(x + Math.cos(angle) * 13 - 15), top: px(y - 27 + Math.sin(angle) * 8), width: px(30), height: px(30))
          @held_weapon.show if @held_weapon.hidden
        else
          @held_weapon.hide unless @held_weapon.hidden
        end
        if (rope = active["rope"])
          @rope_line.style(left: px(x), top: px(y - 12), x2: px(rope['x']), y2: px(rope['y']))
          @rope_line.show if @rope_line.hidden
        else
          @rope_line.hide unless @rope_line.hidden
        end
      end

      def add_particle(x, y, color:, life:, size:, vx:, vy:)
        return if @effects.length >= 100
        @effect_layer.append do
          node = @shoes.oval(px(x), px(y), px(size), fill: color, strokewidth: 0)
          retain_effect(node: node, born: Burrow.clock, life: life, kind: :particle, x: x, y: y, vx: vx, vy: vy)
        end
      end

      def float_text(text, x, y, color)
        @effect_layer.append do
          node = label(text, x - 85, y - 15, 170, size: 19, color: color, font: Theme.display, align: "center")
          retain_effect(node: node, born: Burrow.clock, life: 1.1, kind: :text, x: x - 85, y: y - 15)
        end
      end

      def sprite_effect(name, x, y, scale)
        return if @effects.length >= 100 || !@controller.motion?
        spec = FX.fetch(name)
        width, height = spec["size"].map { |n| n * scale }
        ax, ay = spec["anchor"].map { |n| n * scale }
        @effect_layer.append do
          node = image("fx/#{name}-0", x - ax, y - ay, width, height)
          retain_effect(node: node, born: Burrow.clock, life: spec["frames"].fdiv(spec["fps"]),
            kind: :sprite, name: name, fps: spec["fps"], frame: 0)
        end
      end

      def retain_effect(**effect)
        @effects.shift[:node].remove while @effects.length >= 100
        @effects << effect
      end

      def render_effects(now)
        @effects.delete_if do |effect|
          age = now - effect[:born]
          if age >= effect[:life]
            effect[:node].remove
            true
          else
            case effect[:kind]
            when :sprite
              frame = (age * effect[:fps]).floor
              if frame != effect[:frame]
                path = "fx/#{effect[:name]}-#{frame}"
                cache_frame(path)
                effect[:node].path = File.join(Theme::ART, path + ".png")
                effect[:frame] = frame
              end
            when :particle
              effect[:node].move(px(effect[:x] + effect[:vx] * age), px(effect[:y] + effect[:vy] * age + age * age * 110))
            when :text
              effect[:node].move(px(effect[:x]), px(effect[:y] - age * 24))
            when :ring
              radius = 8 + effect[:radius] * (age / effect[:life])
              effect[:node].style(left: px(effect[:x] - radius), top: px(effect[:y] - radius), width: px(radius * 2), height: px(radius * 2))
            end
            false
          end
        end
      end
    end
  end
end
