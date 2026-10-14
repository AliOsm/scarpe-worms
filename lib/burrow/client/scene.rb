# frozen_string_literal: true

require_relative "terrain_art"
require_relative "camera"
require_relative "timeline"
require_relative "sprites"

module Burrow
  module Client
    class Scene
      include Widgets
      Y = 104
      # Diagonal outline copies keep names legible over any scenery at little paint cost.
      BADGE_OUTLINE = [[-1, -1], [1, -1], [-1, 1], [1, 1]].freeze
      EFFECT_TEXT_OFFSETS = (BADGE_OUTLINE + [[0, 0]]).freeze
      # Each retained caption owns a stack and five paragraphs. Bound the idle
      # pool separately from the 100 live effects so long matches cannot grow it.
      EFFECT_TEXT_POOL_LIMIT = 12
      # Each name builds five native paragraphs. Bound construction to two
      # names per frame so discovering a crowd leaves time for motion and input.
      LABELS_PER_FRAME = 2
      ANIMATIONS = {"idle" => [4, 6], "walk" => [8, 12], "jump" => [4, 8], "hurt" => [3, 9],
        "victory" => [6, 8], "dead" => [1, 1], "tumble" => [4, 14], "dying" => [6, 10],
        "grave" => [4, 12], "drown" => [4, 8]}.transform_values(&:freeze).freeze
      # A fallen grub swells for this long (its six dying frames), then pops into
      # a ghost and leaves its gravestone. Audio::DYING times the pop to match.
      DYING = 0.6
      # A blasted grub spins while it flies, for this long after the hit.
      TUMBLE_SECONDS = 3.0
      DROWN_FRAMES = Array.new(6) do |color|
        ["", "left/"].map { |side| Sprites.frames("grubs/#{side}#{color}-drown-%d", 4).freeze }.freeze
      end.freeze
      # Fill and outline of the word drawn over each comic burst.
      BURST_COLORS = {"pow" => ["#ef3b2c", Theme::INK], "boom" => [Theme::YELLOW, Theme::INK],
        "splash" => [Theme::WHITE, "#1f5bb5"], "spirit" => [Theme::WHITE, "#6a4bb3"]}.freeze
      FLAME_PATHS = Array.new(4) { |i| File.join(Theme::ART, "fx/flame-#{i}.png").freeze }.freeze
      MINE_PATH = File.join(Theme::ART, "mine-prop.png").freeze
      LIT_MINE_PATH = File.join(Theme::ART, "mine-prop-lit.png").freeze
      SEA_BELOW = 1200
      FX = JSON.parse(File.read(File.join(Theme::ART, "manifest.json"), encoding: Encoding::UTF_8)).fetch("extras").fetch("fx_animations").freeze
      COMBAT = JSON.parse(File.read(File.join(Theme::ART, "manifest.json"), encoding: Encoding::UTF_8)).fetch("combat").freeze
      # Everything here repaints with the battlefield: no gradients (Widgets#shade).
      def flat_ui? = true
      attr_reader :terrain_revision, :terrain_packet, :preview_terrain, :actors, :frame_count, :max_frame_ms, :last_frame_ms, :camera, :timeline, :positions, :last_render

      # Inspection tools can request the full collision grid. Normal rendering
      # forwards its compressed packet to the worker without decoding/hashing it
      # on the GUI thread, including on resize and every explosion.
      def terrain = (@terrain ||= Terrain.restore(@terrain_packet) if @terrain_packet)

      def initialize(shoes, controller, scale: 1, presentation: nil)
        @shoes, @controller, @scale = shoes, controller, scale
        @actors, @projectile_nodes, @hazard_nodes, @frame_cache, @hurt_until = {}, {}, {}, {}, {}
        @deaths, @struck_at, @dizzy_until = {}, {}, {}
        @effects = []
        @positions = {}
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
          # Keep the last completed worker result authoritative while the rebuilt
          # scene waits for its first heartbeat. This makes resize state visible
          # immediately and avoids a transient blank revision when no new packet
          # is needed.
          @terrain_revision = @restored_terrain_result[:revision] if @restored_terrain_result
          @terrain_result = @restored_terrain_result
          @last_turn, @finished_at = presentation.values_at(:last_turn, :finished_at)
          @hurt_until = presentation[:hurt_until]
          @deaths, @struck_at, @dizzy_until = presentation.values_at(:deaths, :struck_at, :dizzy_until).map { |table| table || {} }
          @impact_focus = presentation[:impact_focus]
          @strike_focus = presentation[:strike_focus]
          @tracked_projectile = presentation[:tracked_projectile]
          @turn_notice_data = presentation[:turn_notice_data]
          @turn_notice_pending = presentation[:turn_notice_pending]
        end
        @tiles = {}
        @slot = @shoes.stack(left: 0, top: px(Y), width: px(1440), height: px(720)) do
          @backdrop = image("sky-meadow", -48, -24, 1536, 768)
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
            # Pictures attached to grubs (Sprites.overlay_rule): packs, canopies, shields.
            @overlay_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @shot_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            # Drowning grubs sink beneath the opaque water drawn over this layer.
            @sink_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            # Deep, nearly opaque water hides the islands' roots, under a pale crest.
            # It runs on past the world's bottom edge, which a zoomed-out camera can show.
            @water = box(0, @height - 96, @width, 96 + SEA_BELOW, color: "#236f88f4", radius: 0)
            @water_band = box(0, @height - 96, @width, 14, color: "#4fa6b8", radius: 0)
            @waterline = line(0, @height - 96, @width, @height - 96, color: "#e1fbf4", width: 4)
            @effect_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) {}
            @aim_layer = @shoes.stack(left: 0, top: 0, width: px(@width)) do
              @aim_dots = Array.new(15) { @shoes.oval(0, 0, px(4), fill: "#fffaf0cc", stroke: "#182d3566", strokewidth: px(1)) }
              @reticle = @shoes.oval(0, 0, px(24), fill: "#ffffff00", stroke: Theme::INK, strokewidth: px(1.5))
              @lock_marker = image("ui/target-lock", 0, 0, 48, 48)
              @lock_caption = label("LOCKED", 0, 0, 90, size: 12, color: "#ff5a45", font: Theme.display, weight: 700, align: "center")
              @strike_arrow = image("ui/wind-arrow", 0, 0, 64, 32).tap { |arrow| arrow.transform(:center) }
              @placement = line(0, 0, 140, 0, color: "#f2c46ddd", width: 12)
              @teleport_ghost = image("ordnance/mobility/teleport-ghost", 0, 0, 64, 64, alt: "Teleport landing preview")
              @placement_caption = label("", 0, 0, 340, size: 12, color: Theme::WHITE, font: Theme.display, weight: 700, align: "center")
              # Turning sprites pivot on their centres, not their top-left corners.
              @held_weapon = image("weapons/rocket", 0, 0, 30, 30).tap { |held| held.transform(:center) }
              @active_arrow = label("▼", 0, 0, 30, size: 22, color: Theme::ORANGE, align: "center")
              # Two strokes keep the grapple readable against both sky and
              # painted terrain. The hook rotates along the final rope segment.
              @rope_outline = line(0, 0, 0, 0, color: "#182d35", width: 5)
              @rope_line = line(0, 0, 0, 0, color: "#eac386", width: 2)
              @rope_hook = image("ordnance/mobility/grapple-hook", 0, 0, 24, 24, alt: "Grapple hook").tap { |hook| hook.transform(:center) }
              @rope_outline.hide unless @rope_outline.hidden
              @rope_line.hide unless @rope_line.hidden
              @rope_hook.hide unless @rope_hook.hidden
            end
            @cache = @shoes.stack(left: 0, top: 0, width: 1, height: 1) {}
            @cache.hide
          end
          box(10, 6, 336, 72, color: Theme::INK, radius: 20)
          # Overlays on the battlefield repaint as the camera moves: solid fills only.
          box(13, 9, 330, 66, color: "#1f5bb5ee", radius: 17)
          button("Map · G", 22, 16, 108, height: 30, size: 14) { toggle_map }
          button("Follow · F", 140, 16, 108, height: 30, size: 14) { camera.follow }
          @camera_caption = label("", 24, 54, 316, size: 11, color: "#e3f1ff", font: Theme.display, weight: 600)
          map_scale = [286.0 / @width, 128.0 / @height].min
          @map_w, @map_h = @width * map_scale, @height * map_scale
          @map_x, @map_y = 1122 + (286 - @map_w) / 2, 572 + (128 - @map_h) / 2
          box(1108, 536, 316, 178, color: Theme::INK, radius: 22)
          box(1112, 540, 308, 170, color: "#1f5bb5f2", radius: 19)
          box(@map_x - 4, @map_y - 4, @map_w + 8, @map_h + 8, color: Theme::DEEP, radius: 8, stroke: Theme::INK, stroke_width: 2)
          outlined("Map", 1126, 545, 120, size: 15, color: Theme::YELLOW, thickness: 1.5, offsets: Theme::OUTLINE.first(4))
          label("Drag to move view", 1270, 549, 136, size: 11, color: "#e3f1ff", align: "right", font: Theme.display, weight: 600)
          @minimap_layer = @shoes.stack(left: 0, top: 0, width: px(1440), height: px(720)) {}
          @minimap = nil
          @map_marks = {}
          @map_water = box(@map_x, @map_y + @map_h - 6, @map_w, 6, color: "#6dbac4aa", radius: 0)
          @map_frame = box(@map_x, @map_y, @map_w, @map_h, color: "#ffffff00", radius: 0, stroke: "#fffaf0")
          @map_shot = box(0, 0, 6, 6, color: Theme::ORANGE, radius: 3, stroke: Theme::WHITE)
          @map_shot.hide
          @turn_notice = @shoes.stack(left: px(438), top: px(8), width: px(580), height: px(84)) do
            box(3, 3, 574, 78, color: Theme::INK, radius: 28)
            box(6, 6, 568, 72, color: "#2f7fe0", radius: 25)
            box(16, 8, 548, 28, color: "#ffffff26", radius: 18)
            @turn_notice_accent = box(14, 12, 60, 60, color: Theme::ORANGE, radius: 30)
            box(18, 16, 52, 52, color: Theme::DEEP, radius: 26)
            @turn_notice_portrait = image("grubs/0-idle-0", 12, 8, 66, 66)
            @turn_notice_title = outlined("", 88, 13, 470, size: 25, color: Theme::CYAN, thickness: 2, offsets: Theme::OUTLINE.first(4))
            @turn_notice_detail = label("", 89, 49, 470, size: 13, color: Theme::WHITE, font: Theme.display, weight: 600)
          end
          @turn_notice.hide
          @loading_label = outlined("Charting the battlefield…", 400, 310, 640, size: 28, align: "center", thickness: 2)
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
        if @controller.respond_to?(:present_movement)
          @state = @controller.present_movement(@state, terrain: @preview_terrain, now: started)
        end
        if @last_turn != @state["turn"]
          @last_turn = @state["turn"]
          @impact_focus = nil
          @turn_notice_pending = true
          # Exploring a distant island is an explicit player choice. A new turn
          # must not steal the camera back until Follow is requested.
          camera.follow if @frame_count > 1 && camera.following
        end
        active = @state["worms"].find { |w| w["id"] == @state["active"] }
        render_camera(active, started)
        @scale = @ui_scale * camera.zoom
        camera.update_shake(now: started, motion: @controller.motion?)
        render_backdrop
        @last_render = started
        ox, oy = px(-camera.x + camera.shake_x / camera.zoom), px(-camera.y + camera.shake_y / camera.zoom)
        if !@origin || @origin[0] != ox || @origin[1] != oy
          @world.move(ox, oy)
          @origin = [ox, oy]
        end
        resize_world if @world_scale != @scale
        update_terrain if @terrain_art
        render_terrain
        if @terrain_art.error && !@render_error_shown
          @render_error_shown = true
          @controller.notify("The landscape renderer stopped: #{@terrain_art.error}")
        end
        reconcile_actors
        reconcile_objects(@projectile_nodes, @state["projectiles"], @shot_layer, projectile: true)
        reconcile_objects(@hazard_nodes, @state["hazards"], @props_layer, projectile: false)
        @timeline.events.each { |e| event(e); @controller.play_event(e) }
        @finished_at ||= started if @state["phase"] == "finished" && @timeline.tick >= @state["tick"]
        render_actors(started)
        render_overlays
        render_projectiles
        render_strike
        render_hazards
        render_aim(started)
        render_effects(started)
        if @water_level != @state["water"] || @water_scale != @scale
          @water.style(top: px(@state["water"]), width: px(@width), height: px(@height - @state["water"] + SEA_BELOW))
          @water_band.style(top: px(@state["water"]), width: px(@width), height: px(14))
          @waterline.style(strokewidth: px(4))
          @waterline.style(top: px(@state["water"]), x2: px(@width), y2: px(@state["water"]))
          @water_level, @water_scale = @state["water"], @scale
        end
        render_navigation
        render_turn_notice(started, active)
        # Construct one hidden caption during quiet frames, instead of all five
        # paragraphs per victim when the first blast arrives. Work and retained
        # nodes stay bounded; busy frames never pay for preparation.
        prepare_effect_text if @terrain_revision >= 0 && @state["phase"] == "aiming" &&
          @effects.empty? && Burrow.clock - started < 0.004
        elapsed = (Burrow.clock - started) * 1000
        @last_frame_ms = elapsed
        @frame_times << elapsed
        @frame_times.shift if @frame_times.length > 600
        @max_frame_ms = [@max_frame_ms, elapsed].max
      end

      # Effect helpers for Sprites.effect_rule blocks (world coordinates).
      def fx_motion? = @controller.motion?
      def fx_sprite(name, x, y, scale = 1.0) = sprite_effect(name, x, y, scale)
      def fx_particle(x, y, color:, life:, size:, vx: 0, vy: 0) = add_particle(x, y, color: color, life: life, size: size, vx: vx, vy: vy)
      def fx_shake(strength, duration: 0.3) = camera.shake(strength, duration: duration, motion: @controller.motion?)

      # Aircraft belong to a strike's presentation, not the disposable effect
      # pool. Retain one pass so zoom/window rebuilds can redraw its current age.
      def fx_strike(paths, event)
        @strike_focus = {paths: paths, x: event["x"], y: event["y"], vx: event["vx"],
          tick: event.fetch("tick", @timeline.tick), duration: event.fetch("duration", 3.2)}
      end

      # A short-lived image animation: `paths` are full frame paths (Sprites.frames).
      # It may drift (vx/vy, world px per second), loop its frames for `life`
      # seconds and finish on `tail` frames, 0.15 s each (a ghost fading away).
      def fx_frames(paths, x, y, width, height, fps:, anchor_x: width / 2.0, anchor_y: height / 2.0, rotation: nil,
        vx: 0, vy: 0, life: nil, loop: false, tail: [], layer: nil)
        return if @effects.length >= 100 || !@controller.motion?
        (layer || @effect_layer).append do
          node = @shoes.image(paths.first, left: px(x - anchor_x), top: px(y - anchor_y), width: px(width), height: px(height), alt: "")
          if rotation
            node.transform(:center)
            node.rotate(rotation.round)
          end
          retain_effect(node: node, born: Burrow.clock, life: life || paths.length.fdiv(fps), kind: :frames, paths: paths, fps: fps,
            frame: 0, x: x - anchor_x, y: y - anchor_y, width: width, height: height, vx: vx, vy: vy, loop: loop, tail: tail)
        end
        true
      end

      # A word that stays put over its comic burst, readable at any zoom.
      def fx_caption(text, x, y, life:, size:, colors:)
        outlined_effect(text, x, y, colors, size: [px(size), (13 * @ui_scale).round].max, life: life, kind: :caption)
      end

      def fx_line(x, y, x2, y2, color:, width: 2, life: 0.15)
        return if @effects.length >= 100
        @effect_layer.append do
          retain_effect(node: line(x, y, x2, y2, color: color, width: width), born: Burrow.clock, life: life, kind: :line,
            x: x, y: y, x2: x2, y2: y2, width: width)
        end
      end

      def performance
        sorted = @frame_times.sort
        {frames: frame_count, mean_ruby_scene_ms: sorted.empty? ? 0 : sorted.sum / sorted.length,
          p95_ruby_scene_ms: sorted.empty? ? 0 : sorted[(sorted.length * 0.95).floor], max_ruby_scene_ms: max_frame_ms}
      end

      def event(event)
        now = Burrow.clock
        # Close-range poses are presentation state only.  Keeping the short
        # window here means a snapshot/reconnect never changes simulation while
        # an authoritative melee report still gives the grub a readable swing.
        if event["kind"] == "melee" && event["worm"]
          @close_poses ||= {}
          prior = @close_poses[event["worm"]]
          @close_poses[event["worm"]] = {
            tick: event["continuing"] && prior ? prior[:tick] : @timeline.tick,
            style: event["style"], facing: event.fetch("facing", 1),
            angle: event.fetch("angle", event.fetch("facing", 1).negative? ? Math::PI : 0)
          }
        end
        react(event, now)
        # Weapon families can add to, or replace, the default effect (Sprites.effect_rule).
        return if Sprites.effect(self, event, now)
        x, y = event.values_at("x", "y")
        if event["kind"] == "damage"
          @hurt_until[event["worm"]] = now + 0.35
          float_text(event["amount"].to_s, x, y, ["#ef2b1f", Theme::WHITE])
        elsif event["kind"] == "heal"
          float_text("+#{event['amount']}", x, y, ["#4fe06d", Theme::INK])
          sprite_effect("sparkle", x, y, 1.3)
        elsif event["kind"] == "pickup"
          float_text(event["text"], x, y - 15, [Theme::YELLOW, Theme::INK])
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
            retain_effect(node: node, born: now, life: 0.15, kind: :line,
              x: x, y: y, x2: event["x2"], y2: event["y2"], width: event["style"] == "laser" ? 4 : 2)
          end
        end
      end

      def finished_presented? = @finished_at && Burrow.clock - @finished_at > 0.8

      # The state sampled for this frame: the moment its events happened.
      def presented = @state

      def toggle_map
        camera.overview? ? camera.follow : camera.overview
      end

      def navigation_hit?(x, y)
        (x.between?(12, 344) && y.between?(8, 76)) ||
          (x.between?(16, 1066) && y.between?(686, 714)) ||
          (x.between?(1112, 1420) && y.between?(540, 710))
      end

      def minimap_hit?(x, y)
        return false unless @map_x && @map_y && @map_w && @map_h
        x.between?(@map_x, @map_x + @map_w) && y.between?(@map_y, @map_y + @map_h)
      end

      def navigate(x, y)
        return false unless @map_x && @map_y && @map_w && @map_h
        return false unless x.between?(@map_x, @map_x + @map_w) && y.between?(@map_y, @map_y + @map_h)
        camera.navigate((x - @map_x) / @map_w * @width, (y - @map_y) / @map_h * @height)
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
          finished_at: @finished_at, hurt_until: @hurt_until,
          deaths: @deaths, struck_at: @struck_at, dizzy_until: @dizzy_until,
          impact_focus: @impact_focus, strike_focus: @strike_focus, tracked_projectile: @tracked_projectile,
          turn_notice_data: @turn_notice_data, turn_notice_pending: @turn_notice_pending}
        @terrain_art = nil
        saved
      end

      private

      def render_actors(started)
        dense = camera.zoom < 0.7
        labels_built = 0
        @positions.clear
        @state["worms"].each do |worm|
          node = @actors.fetch(worm["id"])
          dead = worm["hp"] <= 0
          if dead
            # A grub already gone when this view began rests in its grave.
            death = (@deaths[worm["id"]] ||= {at: started - 10, popped: true})
            if death[:drowned] || worm["sunk"] || worm["y"] >= @state["water"]
              node[:slot].hide unless node[:slot].hidden
              node[:visible] = false
              next
            end
            age = started - death[:at]
            if !death[:popped] && age >= DYING
              death[:popped] = true
              pop(worm["x"], worm["y"], started)
            end
          end
          x, y = worm["x"], worm["y"]
          position = (node[:world_position] ||= [0, 0])
          position[0], position[1] = x, y
          @positions[worm["id"]] = position
          sx, sy = (x - camera.x) * camera.zoom, (y - camera.y) * camera.zoom
          visible = sx.between?(-90, 1530) && sy.between?(-90, 810)
          # Only the active grub's bounds feed the aim marker off screen. Other
          # hidden actors can adopt a zoom when they next enter the viewport.
          if node[:scale] != @scale && (visible || worm["id"] == @state["active"])
            resize_actor(node, x, y)
          end
          if node[:visible] != visible
            visible ? node[:slot].show : node[:slot].hide
            node[:visible] = visible
          end
          next unless visible
          left, top = px(x) - node[:offset_x], px(y) - node[:offset_y]
          if !node[:position] || node[:position][0] != left || node[:position][1] != top
            node[:slot].move(left, top)
            node[:position] = [left, top]
          end
          state = if dead
            !@controller.motion? || age >= DYING ? "grave" : "dying"
          elsif @state["phase"] == "finished" && worm["team"] == @state["winner"]
            "victory"
          elsif @hurt_until.fetch(worm["id"], 0) > started
            "hurt"
          elsif @struck_at.fetch(worm["id"], -TUMBLE_SECONDS) > started - TUMBLE_SECONDS &&
              (worm["vy"].abs > 40 || Math.hypot(worm["vx"], worm["vy"]) > 110)
            "tumble"
          elsif worm["vy"].abs > 15
            "jump"
          elsif worm["vx"].abs > 8
            "walk"
          else
            "idle"
          end
          count, fps = ANIMATIONS.fetch(state)
          frame = if !@controller.motion?
            state == "grave" ? 3 : 0
          elsif state == "dying"
            [(age * 10).floor, 5].min
          elsif state == "grave"
            [((age - DYING) * 12).floor, 3].min
          elsif state == "hurt"
            [((started - (@hurt_until[worm["id"]] - 0.35)) * fps).floor, 2].min.clamp(0, 2)
          elsif state == "jump"
            worm["vy"] < -30 ? 1 : worm["vy"] > 30 ? 3 : 2
          else
            (started * fps).to_i % count
          end
          # Gravestones are carved to be read from the front.
          facing_left = worm["facing"] < 0 && state != "grave"
          if node[:pose] != state || node[:frame] != frame || node[:facing_left] != facing_left
            path = "grubs/#{facing_left ? 'left/' : ''}#{node[:team]}-#{state}-#{frame}"
            cache_frame(path)
            node[:image].path = File.join(Theme::ART, path + ".png") if node[:path] != path
            node[:path], node[:pose], node[:frame], node[:facing_left] = path, state, frame, facing_left
          end
          tx, ty = @controller.target
          show_badge = worm["hp"] > 0 && (!dense || worm["id"] == @state["active"] || Math.hypot(tx - x, ty - y + 15) * camera.zoom < 22)
          # Status tints the name's outline: frost, a shield's glow or poison.
          outline = worm["frozen"] ? "#1f6fb8" : worm["shield"] ? "#1d8a52" : worm["poisoned"] ? "#6b7d12" : Theme::INK
          if show_badge && !node[:label]
            # Names appear as grubs first come into view, a few per frame, so a
            # six-team match does not build 180 text layers in its first frame.
            labels_built < LABELS_PER_FRAME ? build_label(node, worm, outline) : show_badge = false
            labels_built += 1
          end
          next unless node[:label]
          restyle_label(node) if show_badge && node[:label_scale] != @scale
          if node[:show_badge] != show_badge
            show_badge ? node[:label].show : node[:label].hide
            node[:show_badge] = show_badge
          end
          if show_badge && (node[:label_name] != worm["name"] || node[:label_hp] != worm["hp"])
            set_text(node[:label], "#{worm['name']}\n#{worm['hp']}")
            node[:label_name], node[:label_hp] = worm["name"], worm["hp"]
          end
          node[:label].layers[0...-1].each { |layer| layer.style(stroke: outline) } if node[:outline] != outline
          node[:outline] = outline
        end
      end

      # Grub-attached pictures. Each grub keeps a small pool of image nodes; a
      # pool slot is hidden only when that grub has fewer overlays than before.
      def render_overlays
        tick = @timeline.tick
        @overlay_nodes ||= {}
        if @close_poses && !@close_poses.empty?
          live_ids = @state["worms"].map { |entry| entry["id"] }
          @close_poses.delete_if { |id, pose| !live_ids.include?(id) || tick - pose[:tick] >= 12 }
        end
        effects = @state.fetch("effects", {})
        @state["worms"].each do |worm|
          pool = (@overlay_nodes[worm["id"]] ||= [])
          # Effects and tools are match-level state.  Add short-lived display
          # fields to a dup so Sprites rules stay independent of protocol shape.
          active = worm["id"] == @state["active"]
          pose = @close_poses && @close_poses[worm["id"]]
          tool = active && @state["tool"]
          dizzy = @dizzy_until.fetch(worm["id"], 0) > @last_render
          needs_display = pose || tool || dizzy || (active && (effects["double_damage"] || effects["low_gravity"]))
          display_worm = needs_display ? worm.dup : worm
          if needs_display
            display_worm["_dizzy"] = true if dizzy
            display_worm["_close_boost"] = effects["double_damage"] if active
            display_worm["_close_moon"] = effects["low_gravity"] if active
            display_worm["_close_tool"] = tool if tool
            display_worm["_close_pose"] = pose if pose
          end
          looks = worm["hp"] > 0 && @actors[worm["id"]]&.fetch(:visible, false) ? Sprites.overlays(display_worm, tick) : []
          next if looks.empty? && pool.empty?
          x, y = worm.values_at("x", "y")
          looks.each_with_index do |look, i|
            unless (node = pool[i])
              @overlay_layer.append do
                image = @shoes.image(look.path, left: 0, top: 0, width: 1, height: 1, alt: "").tap { |img| img.transform(:center) }
                node = pool[i] = {image: image, path: look.path}
              end
            end
            if node[:path] != look.path
              node[:image].path = look.path
              node[:path] = look.path
            end
            place(node[:image], px(x - look.anchor_x), px(y - look.anchor_y), px(look.width), px(look.height))
            rotation = look.rotation ? (look.rotation / 3).round * 3 : 0
            node[:image].rotate(rotation) if (node[:image].rotate_angle || 0) != rotation
            show_if(node[:image], true)
          end
          pool.drop(looks.length).each { |node| show_if(node[:image], false) }
        end
      end

      def render_projectiles
        tick = @timeline.tick
        @state["projectiles"].each do |p|
          node = @projectile_nodes[p["id"]]
          x, y = p["x"], p["y"]
          look = Sprites.projectile(p, tick)
          if node[:path] != look.path
            node[:image].path = look.path
            node[:path] = look.path
          end
          place(node[:image], px(x - look.anchor_x), px(y - look.anchor_y), px(look.width), px(look.height))
          if look.rotation
            # Munitions turn in 3° steps; the guided critter's interpolated
            # heading is shown at presentation cadence (6° buckets visibly step).
            step = p["weapon"] == "super_sheep" ? 1 : Sprites::MUNITION_BLASTS.key?(p["weapon"]) ? 3 : 6
            rotation = (look.rotation / step).round * step
            node[:image].rotate(rotation) if node[:image].rotate_angle != rotation
          end
          if node[:fuse]
            badge_scale = @ui_scale * [camera.zoom, 0.8].max
            bw, bh = (34 * badge_scale).round, (22 * badge_scale).round
            bx, by = px(x) - bw / 2, px(y - 19) - bh
            restyle(node[:fuse_plate], left: bx, top: by, width: bw, height: bh)
            restyle(node[:fuse], left: bx, top: by + (3 * badge_scale).round, width: bw, size: [(12 * badge_scale).round, 8].max)
            fuse_text = if p["weapon"] == "holy_bomb" && p["stage"] == "waiting"
              "…"
            elsif p["weapon"] == "holy_bomb" && p["stage"] == "choir"
              "!"
            else
              p["life"] ? "#{(p['life'].fdiv(TICK_RATE)).ceil}s" : ""
            end
            set_text(node[:fuse], fuse_text)
            # A lit fuse spits sparks until it blows.
            if @controller.motion? && @frame_count % 5 == 0 && p["life"].to_i > 0
              add_particle(x + 2, y - 15, color: @frame_count % 10 == 0 ? "#ffe27a" : "#ff9d3b", life: 0.3, size: 3,
                vx: (@frame_count / 5 % 3 - 1) * 24, vy: -40)
            end
            color = p["life"].to_f <= TICK_RATE ? Theme::ORANGE : Theme::WHITE
            node[:fuse].style(stroke: color) if node[:fuse_color] != color
            node[:fuse_color] = color
          end
          if @controller.motion? && !p["walker"]
            if Sprites::MUNITION_BLASTS.key?(p["weapon"])
              Sprites.munition_trail(self, p, rotation: node[:image].rotate_angle) if @frame_count % 6 == 0
            elsif @frame_count % 4 == 0 && Math.hypot(p["vx"], p["vy"]) > 40
              add_particle(x, y, color: "#ffefc188", life: 0.35, size: 7, vx: 0, vy: -8)
            end
          end
        end
      end

      def render_hazards
        @state["hazards"].each do |h|
          node = @hazard_nodes[h["id"]]
          if h["kind"] == "gas" || h["kind"] == "fire"
            radius = h["radius"]
            place(node[:image], px(h["x"] - radius), px(h["y"] - radius), px(radius * 2), px(radius * 2))
          else
            if h["kind"] == "mine" || h["kind"] == "barrel" || h["kind"] == "turret"
              look = Sprites.close_hazard(h, @timeline.tick, motion: @controller.motion?)
              if look
                node[:image].path = look.path if node[:image].path != look.path
                place(node[:image], px(h["x"] - look.anchor_x), px(h["y"] - look.anchor_y),
                  px(look.width), px(look.height))
                next
              end
            end
            width, height, ax, ay = node[:bounds]
            # Props rest most of the time: restyle only those that moved or rescaled.
            place(node[:image], px(h["x"] - ax), px(h["y"] - ay), px(width), px(height))
            if h["kind"] == "flame"
              # Offscreen flames keep their place but skip animation path swaps.
              # Do not hide/show them: toggling visibility while the camera zooms
              # starved native presentation (half the zoom frames went unpainted).
              sx, sy = (h["x"] - camera.x) * camera.zoom, (h["y"] - camera.y) * camera.zoom
              next unless sx.between?(-40, 1480) && sy.between?(-40, 760)
              frame = @controller.motion? ? ((@timeline.tick / 2.5).floor + node[:phase]) % 4 : 0
              if node[:frame] != frame
                node[:image].path = FLAME_PATHS[frame]
                node[:frame] = frame
              end
            elsif h["kind"] == "mine"
              blinking = @controller.motion? && @timeline.tick >= h.fetch("armed", 0)
              lit = h["trigger"] || (blinking && (@timeline.tick / 15).floor.odd?)
              path = lit ? LIT_MINE_PATH : MINE_PATH
              node[:image].path = path if node[:image].path != path
            end
          end
        end
      end

      def render_turn_notice(now, active)
        if @turn_notice_pending && @terrain_revision >= 0 && active && @state["phase"] == "aiming"
          team = @state["teams"].find { |entry| entry["id"] == active["team"] }
          mine = @controller.my_turn?
          @turn_notice_data = {turn: @state["turn"], until: now + (mine ? 2.4 : 1.6), color: team["color"],
            title: mine ? "Your move, #{short_text(active['name'], 18)}" : "#{short_text(team['name'], 24)} takes aim",
            detail: mine ? "Move · Aim · Fire · Get clear" : "#{active['name']} · Round #{@state['round']}"}
          @turn_notice_pending = false
        end
        data = @turn_notice_data
        visible = data && data[:turn] == @state["turn"] && now < data[:until] &&
          @state["phase"] == "aiming" && !@controller.overlay?
        unless visible
          @turn_notice.hide unless @turn_notice.hidden
          return
        end
        if @painted_notice_turn != data[:turn]
          @turn_notice_portrait.path = File.join(Theme::ART, "grubs/#{data[:color]}-idle-0.png")
          @turn_notice_accent.style(fill: COLORS[data[:color]])
          set_text(@turn_notice_title, data[:title])
          @painted_notice_turn = data[:turn]
        end
        detail = @controller.my_turn? && !camera.following ? "F follows your grub · E opens the arsenal" : data[:detail]
        set_text(@turn_notice_detail, detail)
        @turn_notice.show if @turn_notice.hidden
      end

      def render_backdrop
        # A single oversized distant plate moves much less than the landscape.
        # It never affects collision, aim coordinates or the camera's zoom.
        cx, cy = camera.world(720, 360)
        dx = @controller.motion? ? (cx.fdiv(@width) - 0.5).clamp(-0.5, 0.5) * 96 : 0
        dy = @controller.motion? ? (cy.fdiv(@height) - 0.5).clamp(-0.5, 0.5) * 48 : 0
        origin = [((-48 - dx) * @ui_scale).round, ((-24 - dy) * @ui_scale).round]
        @backdrop.move(*origin) if origin != @backdrop_origin
        @backdrop_origin = origin
      end

      def render_camera(active, now)
        shots = @state["projectiles"]
        strike_elapsed = strike_age
        # Keep a flight's identity through packet coalescing and cluster spawns.
        # Timeline shots contain presentation data, not live control flags.
        shot = shots.find { |p| p["id"] == @tracked_projectile } || shots.first
        impact = @timeline.events.reverse.find { |e| %w[explosion splash].include?(e["kind"]) && e["x"] && e["y"] }
        @impact_focus = {point: impact.values_at("x", "y"), until: now + 0.85} if impact
        if shot
          @tracked_projectile = shot["id"]
          target, velocity, mode = shot.values_at("x", "y"), shot.values_at("vx", "vy"), :projectile
        elsif strike_elapsed
          # The approach is visible before the first release. Camera#update
          # honors manual exploration; the first real bomb takes over tracking.
          target = [@strike_focus[:x] + @strike_focus[:vx] * strike_elapsed, @strike_focus[:y]]
          velocity, mode = [@strike_focus[:vx], 0], :projectile
        elsif @impact_focus && now < @impact_focus[:until]
          target, mode = @impact_focus[:point], :impact
        else
          @tracked_projectile = nil
          target, velocity, mode = active&.values_at("x", "y"), nil, :actor
        end
        camera.update(target, velocity: velocity, mode: mode, dt: now - (@last_render || now), animate: @controller.motion?)
      end

      def strike_age
        return unless @strike_focus
        age = [(@timeline.tick - @strike_focus[:tick]).fdiv(TICK_RATE), 0].max
        if age >= @strike_focus[:duration]
          @strike_focus = nil
          return
        end
        age
      end

      def render_strike
        age = strike_age
        unless age && @controller.motion?
          show_if(@strike_node, false) if @strike_node
          return
        end
        pass = @strike_focus
        path = pass[:paths][(age * 12).floor % pass[:paths].length]
        unless @strike_node
          @effect_layer.append { @strike_node = @shoes.image(path, left: 0, top: 0, width: 1, height: 1, alt: "") }
        end
        @strike_node.path = path if @strike_node.path != path
        place(@strike_node, px(pass[:x] + pass[:vx] * age - 72), px(pass[:y] - 49), px(144), px(72))
        show_if(@strike_node, true)
      end

      def resize_world
        @world_scale = @scale
        [@world, @terrain_layer, @props_layer, @actor_layer, @overlay_layer, @shot_layer, @sink_layer, @effect_layer, @aim_layer].compact.each { |layer| layer.style(width: px(@width)) }
        @aim_dots.each { |dot| restyle(dot, width: px(4), height: px(4), strokewidth: [px(1), 1].max) }
        restyle(@reticle, width: px(24), height: px(24))
        restyle(@placement, strokewidth: px(12))
        restyle(@rope_outline, strokewidth: [px(5), 2].max) if @rope_outline
        restyle(@rope_line, strokewidth: [px(2), 1].max) if @rope_line
        restyle(@active_arrow, width: px(30), size: [px(22), 10].max)
      end

      # Native slots clip their children. Enclose the whole name and health,
      # including their minimum readable size in overview, while anchoring the
      # sprite's source foot (80,136 of 160) to the authoritative world position.
      def actor_metrics
        return @actor_metrics if @actor_metrics_scale == @scale
        @actor_metrics_scale = @scale
        label_scale = @ui_scale * [camera.zoom, 0.75].max
        bw, bh = (110 * label_scale).round, (40 * label_scale).round
        width = [px(110), bw].max
        sprite_top = bh + px(3)
        @actor_metrics = {bw: bw, bh: bh, bx: (width - bw) / 2, width: width, height: sprite_top + px(64), sprite_top: sprite_top,
          size: [(15 * label_scale).round, 8].max, edge: [(1.5 * label_scale).round, 1].max}
      end

      def resize_actor(node, x, y)
        node[:scale] = @scale
        m = actor_metrics
        node[:offset_x], node[:offset_y] = m[:width] / 2, m[:sprite_top] + px(54.4)
        left, top = px(x) - node[:offset_x], px(y) - node[:offset_y]
        place(node[:slot], left, top, m[:width], m[:height])
        node[:position] = [left, top]
        place(node[:image], node[:offset_x] - px(32), m[:sprite_top], px(64), px(64))
      end

      # Name layers follow a zoom only once their grub is on screen (see render).
      def restyle_label(node)
        m = actor_metrics
        place(node[:badge], 0, 0, m[:width], m[:height])
        node[:label].layers.zip(BADGE_OUTLINE + [[0, 0]]).each do |layer, (dx, dy)|
          restyle(layer, left: m[:bx] + dx * m[:edge], top: m[:edge] + dy * m[:edge], width: m[:bw], size: m[:size])
        end
        node[:label_scale] = @scale
      end

      def build_label(node, worm, outline)
        m = actor_metrics
        place(node[:badge], 0, 0, m[:width], m[:height])
        text = "#{worm['name']}\n#{worm['hp']}"
        node[:badge].append do
          node[:label] = Outlined.new((BADGE_OUTLINE + [[0, 0]]).map do |dx, dy|
            @shoes.para(text, left: m[:bx] + dx * m[:edge], top: m[:edge] + dy * m[:edge], width: m[:bw], size: m[:size],
              stroke: dx.zero? && dy.zero? ? COLORS[node[:team]] : outline, font: Theme.display, weight: 700, align: "center", margin: 0)
          end, container: node[:badge])
        end
        node[:show_badge], node[:outline], node[:label_scale] = true, outline, @scale
        node[:label_name], node[:label_hp] = worm["name"], worm["hp"]
      end

      def place_tile(tile)
        place(tile[:node], px(tile[:x]), px(tile[:y]), px(tile[:x] + tile[:width]) - px(tile[:x]), px(tile[:y] + tile[:height]) - px(tile[:y]))
        tile[:scale] = @scale
      end

      # Native clipping keeps offscreen tiles out of the paint without visibility
      # changes. Defer their geometry only while both the desired bounds and the
      # retained pixel bounds remain outside: a new world origin can otherwise
      # bring stale geometry onscreen. Keep the same rounded adjacent edges and
      # a margin for fractional world-origin, tile and viewport rounding.
      def render_terrain
        margin = 2.0 / @scale
        left, top = camera.x - margin, camera.y - margin
        right = camera.x + Camera::VIEW_WIDTH / camera.zoom + margin
        bottom = camera.y + Camera::VIEW_HEIGHT / camera.zoom + margin
        ox, oy = px(-camera.x), px(-camera.y)
        pixel_left, pixel_top = -ox - 2, -oy - 2
        pixel_right = (Camera::VIEW_WIDTH * @ui_scale).round - ox + 2
        pixel_bottom = (Camera::VIEW_HEIGHT * @ui_scale).round - oy + 2
        @tiles.each_value do |tile|
          next if tile[:scale] == @scale
          node = tile[:node]
          visible = tile[:x] <= right && tile[:x] + tile[:width] >= left &&
            tile[:y] <= bottom && tile[:y] + tile[:height] >= top
          retained_visible = node.left <= pixel_right && node.left + node.width >= pixel_left &&
            node.top <= pixel_bottom && node.top + node.height >= pixel_top
          place_tile(tile) if visible || retained_visible
        end
      end

      def update_terrain
        return unless (result = @terrain_art.poll || @restored_terrain_result)
        @restored_terrain_result = nil
        @terrain_result = result
        @preview_terrain = result[:preview_terrain]
        result[:tiles].each do |spec|
          # Worker results contain only serializable texture metadata, never UI
          # nodes from the previous window layout.
          tile = spec.dup
          if (existing = @tiles[tile[:id]])
            existing[:node].path = tile[:path] if existing[:path] != tile[:path]
            existing[:scale] = nil unless %i[x y width height].all? { |key| existing[key] == tile[key] }
            existing.merge!(tile)
          else
            @terrain_layer.append do
              tile[:node] = @shoes.image(tile[:path], left: px(tile[:x]), top: px(tile[:y]), width: px(tile[:x] + tile[:width]) - px(tile[:x]), height: px(tile[:y] + tile[:height]) - px(tile[:y]), alt: "Destructible landscape")
            end
            tile[:scale] = @scale
            @tiles[tile[:id]] = tile
          end
        end
        saved, @scale = @scale, @ui_scale
        if @minimap
          @minimap.path = result[:overview]
        else
          @minimap_layer.append do
            @minimap = @shoes.image(result[:overview], left: px(@map_x), top: px(@map_y), width: px(@map_w), height: px(@map_h))
          end
        end
        @scale = saved
        @terrain_revision = result[:revision]
        @loading_label.hide unless @loading_label.hidden
      end

      def render_navigation
        saved, @scale = @scale, @ui_scale
        percent = (camera.zoom * 100).round
        if @caption_zoom != percent || @caption_following != camera.following
          set_text(@camera_caption, "#{percent}%  #{camera.following ? 'FOLLOW' : 'FREE'}  ·  Wheel / pinch zoom · drag pan")
          @caption_zoom, @caption_following = percent, camera.following
        end
        water_y = @state["water"].fdiv(@height).clamp(0, 1) * @map_h
        restyle(@map_water, top: px(@map_y + water_y), height: px(@map_h - water_y))
        @state["worms"].each do |w|
          unless @map_marks[w["id"]]
            @slot.append { @map_marks[w["id"]] = box(0, 0, 5, 5, color: COLORS[@state["teams"].find { |t| t["id"] == w["team"] }["color"]], radius: 2) }
          end
          dot = @map_marks[w["id"]]
          if w["hp"] <= 0
            dot.hide unless dot.hidden
          else
            move_to(dot, px(@map_x + w["x"] / @width * @map_w - 2), px(@map_y + w["y"] / @height * @map_h - 2))
          end
        end
        left, top = [camera.x, 0].max, [camera.y, 0].max
        right, bottom = [camera.x + 1440 / camera.zoom, @width].min, [camera.y + 720 / camera.zoom, @height].min
        if right > left && bottom > top
          @map_frame.show if @map_frame.hidden
          place(@map_frame, px(@map_x + left / @width * @map_w), px(@map_y + top / @height * @map_h),
            px((right - left) / @width * @map_w), px((bottom - top) / @height * @map_h))
        else
          @map_frame.hide unless @map_frame.hidden
        end
        if (shot = @state["projectiles"].first) && shot["y"].between?(0, @height)
          move_to(@map_shot, px(@map_x + shot["x"] / @width * @map_w - 3), px(@map_y + shot["y"] / @height * @map_h - 3))
          @map_shot.show if @map_shot.hidden
        else
          @map_shot.hide unless @map_shot.hidden
        end
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
          # Built at its final size: a six-team match adds 36 of these in one frame.
          m = actor_metrics
          node = {team: color, scale: @scale, offset_x: m[:width] / 2, offset_y: m[:sprite_top] + px(54.4)}
          @actor_layer.append do
            node[:slot] = @shoes.stack(left: 0, top: 0, width: m[:width], height: m[:height]) do
              node[:image] = @shoes.image(File.join(Theme::ART, "grubs/#{color}-idle-0.png"), left: node[:offset_x] - px(32),
                top: m[:sprite_top], width: px(64), height: px(64), alt: "")
              # Hide or reveal an outlined name with one property change. Its
              # full actor bounds preserve the original text clipping exactly.
              node[:badge] = @shoes.stack(left: 0, top: 0, width: m[:width], height: m[:height]) {}
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
          node[:fuse_plate]&.remove
        end
        objects.each do |p|
          next if nodes[p["id"]]
          layer.append do
            kind = p["kind"]
            bounds = {"mine" => [34, 34, 17, 27.625], "barrel" => [32, 38.4, 16, 36.8],
                      "crate" => [34, 34, 17, 31.875], "flame" => [24, 32, 12, 30]}.fetch(kind, [32, 32, 16, 29])
            look = projectile ? Sprites.projectile(p, @timeline.tick) : nil
            picture = if projectile
              @shoes.image(look.path, left: px(p["x"] - look.anchor_x), top: px(p["y"] - look.anchor_y),
                width: px(look.width), height: px(look.height), alt: "").tap { |shot| shot.transform(:center) }
            elsif %w[fire gas].include?(kind)
              @shoes.oval(px(p["x"] - p["radius"]), px(p["y"] - p["radius"]), px(p["radius"] * 2),
                fill: kind == "gas" ? "#a3b56366" : "#f57c4966", strokewidth: 0)
            else
              art = if kind == "flame"
                "fx/flame-0"
              elsif kind == "crate"
                supply = Catalog::WEAPONS[p["supply"]]
                p["supply"] == "health" ? "crate-health" : supply && Catalog::UTILITY.include?(supply[:kind]) ? "crate-utility" : "crate"
              else
                {"mine" => "mine-prop", "barrel" => "barrel-prop"}.fetch(kind, "weapons/#{kind}")
              end
              width, height, ax, ay = bounds
              image(art, p["x"] - ax, p["y"] - ay, width, height)
            end
            nodes[p["id"]] = {image: picture, bounds: bounds, phase: p["id"].to_s.sum % 4, path: look&.path}
            if projectile && p["fused"]
              nodes[p["id"]][:fuse_plate] = box(0, 0, 34, 22, color: "#071731eb", radius: 11, stroke: Theme::YELLOW)
              nodes[p["id"]][:fuse] = label("", 0, 0, 34, size: 12, color: Theme::WHITE, font: Theme.display, weight: 700, align: "center")
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
        marker_scale = @ui_scale * [camera.zoom, 0.75].max
        marker_width = (30 * marker_scale).round
        restyle(@active_arrow, left: px(x) - marker_width / 2,
          top: px(y) - @actors.fetch(active["id"])[:offset_y] - (28 * marker_scale).round + px(@controller.motion? ? Math.sin(now * 5) * 3 : 0),
          width: marker_width, size: (22 * marker_scale).round)
        can_aim = @controller.my_turn? && @state["phase"] == "aiming" && !@controller.overlay?
        weapon = Catalog.fetch(@controller.selected_weapon)
        aimed = can_aim && Catalog::AIMED.include?(weapon[:kind]) && !@controller.special_control
        angle = @controller.angle * Math::PI / 180
        cos, sin = Math.cos(angle), Math.sin(angle)
        speed = weapon[:id] == "mortar" ? 580 : 130 + @controller.power * 540
        ballistic = Catalog::CHARGED.include?(weapon[:kind])
        gravity = 285 * @state.dig("config", "gravity") * (@state.dig("effects", "low_gravity") ? 0.45 : 1) if aimed
        wind = ballistic && (weapon[:id] == "rocket" || weapon[:id] == "homing")
        @aim_dots.each_with_index do |dot, i|
          if aimed
            distance = 26 + i * 10
            t = (distance - 20) / speed
            drift = wind ? @state["wind"] * 21 * t * t : 0
            fall = ballistic ? 0.5 * gravity * t * t : 0
            move_to(dot, px(x + cos * distance + drift - 2), px(y - 13 + sin * distance + fall - 2))
            dot.show if dot.hidden
          else
            dot.hide unless dot.hidden
          end
        end
        targeted = can_aim && Catalog::TARGETED.include?(weapon[:kind]) && !@controller.special_control
        placement = @controller.placement_preview if targeted && %w[teleport girder].include?(weapon[:kind])
        placement_color = placement && placement[:valid] == false ? "#ff5a45" : placement && placement[:valid] ? "#7ee35a" : "#f2c46d"
        if targeted
          tx, ty = @controller.target
          ty = placement[:y] if weapon[:kind] == "teleport" && placement && placement[:valid]
          move_to(@reticle, px(tx - 12), px(ty - 12))
          restyle(@reticle, stroke: placement ? placement_color : Theme::INK)
          @reticle.show if @reticle.hidden
        else
          @reticle.hide unless @reticle.hidden
        end
        if placement
          tx, ty = @controller.target
          ty = placement[:y] if weapon[:kind] == "teleport" && placement[:valid]
          set_text(@placement_caption, placement[:message])
          restyle(@placement_caption, left: px(tx) - (170 * marker_scale).round, top: px(ty) + (20 * marker_scale).round,
            width: (340 * marker_scale).round, size: (12 * marker_scale).round, stroke: placement_color)
          @placement_caption.show if @placement_caption.hidden
        else
          @placement_caption.hide unless @placement_caption.hidden
        end
        if targeted && weapon[:kind] == "teleport" && placement && placement[:valid]
          tx = @controller.target[0]
          place(@teleport_ghost, px(tx - 32), px(placement[:y] - 54.4), px(64), px(64))
          @teleport_ghost.show if @teleport_ghost.hidden
        else
          @teleport_ghost.hide unless @teleport_ghost.hidden
        end
        # A homing rocket's destination stays marked from lock-on until impact.
        locked = (@controller.locked_target if can_aim && weapon[:id] == "homing") ||
          @latest["projectiles"].find { |p| p["homing"] && p["target_x"] }&.values_at("target_x", "target_y")
        if locked
          tx, ty = locked
          size = (48 * marker_scale * (@controller.motion? ? 1 + Math.sin(now * 6) * 0.06 : 1)).round
          place(@lock_marker, px(tx) - size / 2, px(ty) - size / 2, size, size)
          @lock_marker.show if @lock_marker.hidden
          caption = [px(tx) - (45 * marker_scale).round, px(ty) + (26 * marker_scale).round, (90 * marker_scale).round, (12 * marker_scale).round]
          if @lock_caption_at != caption
            @lock_caption.style(left: caption[0], top: caption[1], width: caption[2], size: caption[3])
            @lock_caption_at = caption
          end
          @lock_caption.show if @lock_caption.hidden
        else
          @lock_marker.hide unless @lock_marker.hidden
          @lock_caption.hide unless @lock_caption.hidden
        end
        if targeted && Catalog::SKY.include?(weapon[:kind]) && weapon[:kind] != "meteor"
          # The bombers' approach: an arrow upwind of the target, pointing along the flight.
          tx, ty = @controller.target
          side = @controller.strike_direction
          width, height = (64 * marker_scale).round, (32 * marker_scale).round
          place(@strike_arrow, px(tx) - width / 2 - side * (52 * marker_scale).round, px(ty) - (64 * marker_scale).round,
            width, height)
          rotation = side.negative? ? 180 : 0
          @strike_arrow.rotate(rotation) if @strike_arrow.rotate_angle != rotation
          @strike_arrow.show if @strike_arrow.hidden
        else
          @strike_arrow.hide unless @strike_arrow.hidden
        end
        if targeted && weapon[:kind] == "girder"
          tx, ty = @controller.target
          tilt = @controller.girder_rotation * Math::PI / 180
          dx, dy = Math.cos(tilt) * 70, Math.sin(tilt) * 70
          restyle(@placement, left: px(tx - dx), top: px(ty + 6 - dy), x2: px(tx + dx), y2: px(ty + 6 + dy),
            stroke: "#{placement_color}dd")
          @placement.show if @placement.hidden
        else
          @placement.hide unless @placement.hidden
        end
        if can_aim && !@controller.special_control
          directional = COMBAT["held"].include?(weapon[:id])
          left = cos.negative?
          if @held_id != weapon[:id] || @held_left != left
            folder = directional ? "held/#{left ? 'left/' : ''}" : "weapons/"
            path = File.join(Theme::ART, "#{folder}#{weapon[:id]}.png")
            @held_weapon.path = path if @held_weapon.path != path
            @held_id, @held_left = weapon[:id], left
          end
          size = directional ? 44 : 30
          reach = directional ? 17 : 13
          place(@held_weapon, px(x + cos * reach - size / 2), px(y - 13 + sin * reach - size / 2), px(size), px(size))
          rotation = directional ? (@controller.angle + (left ? 180 : 0)).round : 0
          @held_weapon.rotate(rotation) if @held_weapon.rotate_angle != rotation
          @held_weapon.show if @held_weapon.hidden
        else
          @held_weapon.hide unless @held_weapon.hidden
        end
        if (rope = active["rope"])
          endpoint_x, endpoint_y = rope.values_at("x", "y")
          endpoint_x ||= x
          endpoint_y ||= y - 12
          hand_x = x + (active["facing"].to_f >= 0 ? 8 : -8)
          hand_y = y - 14
          restyle(@rope_outline, left: px(hand_x), top: px(hand_y), x2: px(endpoint_x), y2: px(endpoint_y))
          restyle(@rope_line, left: px(hand_x), top: px(hand_y), x2: px(endpoint_x), y2: px(endpoint_y))
          angle = Math.atan2(endpoint_y - hand_y, endpoint_x - hand_x) * 180 / Math::PI
          size = (24 * marker_scale).round
          place(@rope_hook, px(endpoint_x) - size / 2, px(endpoint_y) - size / 2, size, size)
          @rope_hook.rotate(angle.round) if @rope_hook.rotate_angle != angle.round
          @rope_outline.show if @rope_outline.hidden
          @rope_line.show if @rope_line.hidden
          @rope_hook.show if @rope_hook.hidden
        else
          @rope_outline.hide unless @rope_outline.hidden
          @rope_line.hide unless @rope_line.hidden
          @rope_hook.hide unless @rope_hook.hidden
        end
      end

      def add_particle(x, y, color:, life:, size:, vx:, vy:)
        return if @effects.length >= 100
        @effect_layer.append do
          node = @shoes.oval(px(x), px(y), px(size), fill: color, strokewidth: 0)
          retain_effect(node: node, born: Burrow.clock, life: life, kind: :particle, x: x, y: y, vx: vx, vy: vy, size: size)
        end
      end

      def float_text(text, x, y, color)
        outlined_effect(text, x, y, color, size: [px(22), (15 * @ui_scale).round].max, life: 1.15, kind: :text)
      end

      def outlined_effect(text, x, y, color, size:, life:, kind:)
        # The text stays readable in overview; its bounds must retain the same
        # display-space padding and width instead of shrinking with the world.
        width = [(text.length * size * 0.7 + 20 * @ui_scale).round, (260 * @ui_scale).round].min
        padding = [(4 * @ui_scale).round, 3].max
        edge = [(2 * @ui_scale).round, 1].max
        height = (size * 1.4).ceil + padding * 2
        left = x - width.fdiv(@scale * 2)
        top = kind == :caption ? y - height.fdiv(@scale * 2) : y - 20 - height.fdiv(@scale)
        fill, outline = color
        if (node = @effect_text_pool&.pop)
          # Reappend even under the same parent: new effects must still paint
          # above older ones, exactly as a newly constructed caption would.
          node.set_parent(@effect_layer)
          place(node, px(left), px(top), width, height)
          node.children.each_with_index do |layer, index|
            dx, dy = EFFECT_TEXT_OFFSETS[index]
            set_text(layer, text)
            restyle(layer, left: dx * edge, top: padding + dy * edge, width: width, size: size,
              stroke: dx.zero? && dy.zero? ? fill : outline)
          end
          node.show
        else
          node = build_effect_text(text, left: px(left), top: px(top), width: width, height: height,
            size: size, padding: padding, edge: edge, fill: fill, outline: outline)
        end
        retain_effect(node: node, born: Burrow.clock, life: life, kind: kind, x: x, y: y, width: width, height: height)
      end

      def build_effect_text(text, left:, top:, width:, height:, size:, padding:, edge:, fill:, outline:, hidden: false)
        node = nil
        @effect_layer.append do
          node = @shoes.stack(left: left, top: top, width: width, height: height, hidden: hidden) do
            EFFECT_TEXT_OFFSETS.each do |dx, dy|
              @shoes.para(text, left: dx * edge, top: padding + dy * edge, width: width, size: size,
                stroke: dx.zero? && dy.zero? ? fill : outline, font: Theme.display, weight: 700, align: "center", margin: 0)
            end
          end
        end
        node
      end

      def prepare_effect_text
        pool = (@effect_text_pool ||= [])
        return unless @effects.empty? && pool.length < EFFECT_TEXT_POOL_LIMIT
        pool << build_effect_text("", left: 0, top: 0, width: 1, height: 1,
          size: 15, padding: 3, edge: 1, fill: Theme::WHITE, outline: Theme::INK, hidden: true)
      end

      # Presentation-only reactions to the host's reports: who reels, who spins,
      # who is about to pop. They never feed back into play.
      def react(event, now)
        id = event["worm"]
        case event["kind"]
        when "damage"
          @struck_at[id] = now
          victim = @state["worms"].find { |w| w["id"] == id }
          if victim && victim["hp"] > 0 && event["amount"].to_i >= 25
            @dizzy_until[id] = now + 2.4
            comic("pow", "OUCH!", event["x"], event["y"] - 36, now) if event["amount"].to_i >= 40
          end
        when "defeat"
          @deaths[id] = {at: now} if id
        when "splash"
          drown(event, now) if id
        when "melee"
          unless Array(event["hits"]).empty?
            word = Sprites::MELEE_WORDS.fetch(event["style"], "POW!")
            comic("pow", word, event["x"] + event.fetch("facing", 1) * 34, event["y"] - 30, now)
          end
        when "explosion"
          radius = event.fetch("radius", 0)
          comic("boom", radius >= 70 ? "KABOOM!" : "BOOM!", event["x"], event["y"] - radius * 0.5 - 30, now) if radius >= 56
        end
      end

      # Comic words are a garnish: at most one starts every 0.3 s.
      def comic(style, word, x, y, now)
        return if now - (@comic_at || -1) < 0.3
        @comic_at = now if Sprites.burst(self, style, word, x, y, colors: BURST_COLORS.fetch(style))
      end

      # The swollen grub bursts into a puff and its little ghost floats away.
      def pop(x, y, now)
        Sprites.reaction(self, "poof", x, y - 18)
        ghost = Sprites::REACTION_FRAMES.fetch("ghost")
        fx_frames(ghost.first(4), x, y - 28, 48, 56, fps: 10, anchor_x: 24, anchor_y: 40, vy: -46, life: 1.7,
          loop: true, tail: ghost.last(2))
        comic("spirit", "BYE BYE!", x, y - 78, now)
      end

      # The grub flails at the surface, then sinks under the opaque water.
      def drown(event, now)
        id = event["worm"]
        @deaths[id] = {at: now, drowned: true, popped: true}
        worm = @state["worms"].find { |w| w["id"] == id }
        team = worm && @state["teams"].find { |t| t["id"] == worm["team"] }
        x, water = event["x"], @state["water"]
        if team
          paths = DROWN_FRAMES.fetch(team["color"])[worm["facing"].to_i.negative? ? 1 : 0]
          # Head and shoulders show above the surface for about a second.
          fx_frames(paths, x, water + 10, 64, 64, fps: 8, anchor_x: 32, anchor_y: 54.4, vy: 30, life: 1.6,
            loop: true, layer: @sink_layer)
        end
        Sprites.reaction(self, "bubbles", x, water + 2)
        comic("splash", "SPLOOSH!", x, water - 58, now)
      end

      # Frames past the end of `paths` index the fading `tail`.
      def effect_frame(effect, age)
        paths, tail = effect[:paths], effect.fetch(:tail, [])
        fading = tail.empty? ? -1 : age - (effect[:life] - tail.length * 0.15)
        if fading >= 0
          paths.length + [(fading / 0.15).floor, tail.length - 1].min
        elsif effect[:loop]
          (age * effect[:fps]).floor % paths.length
        else
          [(age * effect[:fps]).floor, paths.length - 1].min
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
            kind: :sprite, name: name, fps: spec["fps"], frame: 0, x: x - ax, y: y - ay, width: width, height: height)
        end
      end

      def retain_effect(**effect)
        release_effect(@effects.shift) while @effects.length >= 100
        @effects << effect
      end

      def release_effect(effect)
        node = effect[:node]
        # The outlined stack already owns its five paragraphs. Reuse that tree
        # without a second set of child references in every live effect record.
        text = effect[:kind] == :text || effect[:kind] == :caption
        if text && node.respond_to?(:children) && (@effect_text_pool ||= []).length < EFFECT_TEXT_POOL_LIMIT
          node.hide
          @effect_text_pool << node
        else
          node.remove
        end
      end

      def render_effects(now)
        @effects.delete_if do |effect|
          # Events are created after the frame's timestamp was sampled. Their
          # first paint must still use frame zero, never an invalid "--1.png".
          age = [now - effect[:born], 0].max
          if age >= effect[:life]
            release_effect(effect)
            true
          else
            case effect[:kind]
            when :frames
              place(effect[:node], px(effect[:x] + effect.fetch(:vx, 0) * age), px(effect[:y] + effect.fetch(:vy, 0) * age),
                px(effect[:width]), px(effect[:height]))
              frame = effect_frame(effect, age)
              if frame != effect[:frame]
                paths = effect[:paths]
                effect[:node].path = frame < paths.length ? paths[frame] : effect[:tail][frame - paths.length]
                effect[:frame] = frame
              end
            when :sprite
              place(effect[:node], px(effect[:x]), px(effect[:y]), px(effect[:width]), px(effect[:height]))
              frame = (age * effect[:fps]).floor
              if frame != effect[:frame]
                path = "fx/#{effect[:name]}-#{frame}"
                cache_frame(path)
                effect[:node].path = File.join(Theme::ART, path + ".png")
                effect[:frame] = frame
              end
            when :particle
              place(effect[:node], px(effect[:x] + effect[:vx] * age), px(effect[:y] + effect[:vy] * age + age * age * 110), px(effect[:size]), px(effect[:size]))
            when :text
              # A floating caption keeps its readable screen size while its
              # world anchor follows a zoom; do not erase damage on camera input.
              move_to(effect[:node], px(effect[:x]) - effect[:width] / 2, px(effect[:y] - 20 - age * 24) - effect[:height])
            when :caption
              move_to(effect[:node], px(effect[:x]) - effect[:width] / 2, px(effect[:y]) - effect[:height] / 2)
            when :line
              restyle(effect[:node], left: px(effect[:x]), top: px(effect[:y]), x2: px(effect[:x2]), y2: px(effect[:y2]), strokewidth: px(effect[:width]))
            when :ring
              radius = 8 + effect[:radius] * (age / effect[:life])
              restyle(effect[:node], left: px(effect[:x] - radius), top: px(effect[:y] - radius), width: px(radius * 2), height: px(radius * 2), strokewidth: px(5))
            end
            false
          end
        end
      end
    end
  end
end
