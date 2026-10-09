# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

class EncodingTest < Minitest::Test
  # Isolate the locale in another VM; changing this test runner's locale would
  # neither change Ruby's startup encoding nor cover the worker process boundary.
  def under_ascii_locale(source)
    Dir.mktmpdir do |temporary|
      # mktmpdir strips non-ASCII prefix bytes; use a real Unicode subdirectory.
      installation = File.join(temporary, "Brigade \u00C9quipe")
      Dir.mkdir(installation)
      File.symlink(File.expand_path("../lib", __dir__), File.join(installation, "lib"))
      Dir.mkdir(File.join(installation, "extra"))
      output, error, status = Open3.capture3(
        {"LC_ALL" => "C", "LANG" => "C", "RUBYOPT" => nil, "BURROW_RUBY" => RbConfig.ruby,
         "BUNDLE_GEMFILE" => nil, "BUNDLE_BIN_PATH" => nil, "BUNDLER_SETUP" => nil, "RUBYGEMS_GEMDEPS" => nil,
         "RUBYLIB" => File.join(installation, "extra"), "BURROW_TEST_INSTALL_LIB" => File.join(installation, "lib")},
        RbConfig.ruby, "-EUS-ASCII", "-I", $LOAD_PATH.join(File::PATH_SEPARATOR), "-e", <<~RUBY + source)
          # RUBYLIB paths retain the startup locale's encoding even after boot
          # chooses UTF-8. Runtime-added paths have UTF-8; the worker must accept
          # both without transcoding or losing the installed directory's bytes.
          $LOAD_PATH.unshift(ENV.fetch("BURROW_TEST_INSTALL_LIB").dup.force_encoding(Encoding::UTF_8))
          require "burrow"
          require "tmpdir"
          raise "Expected an ASCII startup locale" unless Encoding.default_external == Encoding::US_ASCII
          def wait_for
            deadline = Burrow.clock + 12
            loop do
              value = yield
              return value if value
              raise "Timed out" if Burrow.clock >= deadline
              sleep 0.01
            end
          end
      RUBY
      assert status.success?, "ASCII-locale subprocess failed:\n#{output}\n#{error}"
    end
  end

  def test_host_workers_start_and_restore_unicode_matches_with_tcp_and_tls
    under_ascii_locale(<<~'RUBY')
      require "burrow/server/process"
      require "burrow/server/certificate"
      require "burrow/client/connection"
      # The old boot.rb did this, but its child VMs still defaulted to US-ASCII.
      Encoding.default_external = Encoding::UTF_8
      Dir.mktmpdir do |temporary|
        directory = File.join(temporary, "Burrow\u00A0Jos\u00E9")
        Dir.mkdir(directory)
        [false, true].each do |tls|
          options = {host: "127.0.0.1", port: 0, data_dir: File.join(directory, tls ? "host" : "local")}
          if tls
            options[:certificate], options[:key] = Burrow::Server::Certificate.ensure_pair(File.join(directory, "tls"))
          end
          token = id = match_id = nil
          2.times do |launch|
            host = Burrow::Server::ProcessHost.new(**options)
            client = Burrow::Client::Connection.new(endpoint: "#{tls ? 'tls' : 'tcp'}://127.0.0.1:#{host.port}",
              name: "\u00C9quipe \u0628\u0631\u062C", token: token, fingerprint: host.fingerprint, reconnect: false).connect
            wait_for { client.status == "online" }
            if launch.zero?
              token, id = client.token, client.id
              raise "Create was rejected" unless client.send_action("create", name: "Pip\u00A0Brigade", bots: 1)
              wait_for { client.poll.dig(:state, "room") }
              raise "Start was rejected" unless client.send_action("start")
            end
            state = wait_for { value = client.poll[:state]; value if value && value["match"] }
            raise "Unicode room name changed" unless state.dig("room", "name") == "Pip\u00A0Brigade"
            raise "Unicode player name changed" unless state.dig("room", "members", 0, "name") == "\u00C9quipe \u0628\u0631\u062C"
            raise "Session was replaced" unless client.id == id
            raise "Match was replaced on restart" if match_id && state.dig("room", "match_id") != match_id
            match_id = state.dig("room", "match_id")
            raise "Missing match ID" unless match_id
          ensure
            client&.close
            host&.stop
          end
        end
      end
    RUBY
  end

  def test_preferences_and_checkpoints_are_utf8_regardless_of_locale
    under_ascii_locale(<<~'RUBY')
      require "burrow/client/preferences"
      require "burrow/server/reactor"
      Dir.mktmpdir do |directory|
        path = File.join(directory, "preferences.json")
        preferences = Burrow::Client::Preferences.new(path)
        preferences["name"] = "Pip\u00A0Brigade"
        raise "Preferences lost Unicode" unless Burrow::Client::Preferences.new(path)["name"] == preferences["name"]
        Burrow.atomic_json(File.join(directory, "server.json"), version: 1, rooms: [], sessions: {"probe" => {name: preferences["name"]}})
        host = Burrow::Server::Reactor.new(port: 0, data_dir: directory, logger: Logger.new(File::NULL))
        raise "Checkpoint lost Unicode" unless host.sessions.fetch("probe")[:name] == preferences["name"]
        host.stop
        host.run
      end
    RUBY
  end

  def test_terrain_worker_returns_unicode_paths_under_an_ascii_locale
    under_ascii_locale(<<~'RUBY')
      require "burrow/client/terrain_art"
      Encoding.default_external = Encoding::UTF_8
      Dir.mktmpdir do |temporary|
        directory = File.join(temporary, "Burrow\u00A0terrain")
        Dir.mkdir(directory)
        ENV["TMPDIR"] = directory
        worker = Burrow::Client::TerrainArt.new
        terrain = Burrow::Terrain.new(seed: 291, width: 1440, height: 720)
        worker.request(terrain, "meadow")
        result = wait_for do
          raise worker.error if worker.error
          worker.poll
        end
        raise "Terrain checksum changed" unless result[:checksum] == terrain.checksum
        paths = result[:tiles].map { |tile| tile[:path] } + [result[:overview]]
        raise "Terrain paths were damaged" unless paths.all? { |path| path.start_with?(directory) && File.file?(path) }
      ensure
        worker&.close
      end
    RUBY
  end
end
