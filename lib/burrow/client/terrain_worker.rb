# frozen_string_literal: true
# Deliberately a process: MRI threads share a lock with the animation loop.
require_relative "../../burrow"
require_relative "terrain_painter"
require_relative "../mac_activity"
STDIN.set_encoding(Encoding::UTF_8)
STDOUT.sync = true
painter = Burrow::Client::TerrainPainter.new(ARGV.fetch(0))
activity = Burrow::MacActivity.new("Burrow Brigade landscape generation", precise: false)
STDIN.each_line do |line|
  begin
    activity.active = true
    job = JSON.parse(line)
    terrain = Burrow::Terrain.restore(job.fetch("terrain"))
    puts JSON.generate(painter.render(terrain, job.fetch("biome")))
  ensure
    activity.close
  end
end
