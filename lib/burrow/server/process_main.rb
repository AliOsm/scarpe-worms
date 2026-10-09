# frozen_string_literal: true

require_relative "reactor"
require_relative "certificate"
STDIN.set_encoding(Encoding::UTF_8)
STDOUT.sync = true
begin
  options = JSON.parse(STDIN.gets || "{}", symbolize_names: true)
  server = Burrow::Server::Reactor.new(**options, logger: Logger.new(File::NULL))
  %w[INT TERM].each { |signal| Signal.trap(signal) { server.stop } }
  Thread.new { STDIN.read; server.stop }
  puts JSON.generate(port: server.port, fingerprint: server.fingerprint)
  server.run
rescue StandardError => error
  puts JSON.generate(error: error.message)
  exit 1
end
