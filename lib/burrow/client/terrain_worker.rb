# frozen_string_literal: true
# Deliberately a process: MRI threads share a lock with the animation loop.
require_relative "../../burrow"
require_relative "terrain_painter"
require_relative "../mac_activity"
STDIN.set_encoding(Encoding::UTF_8)
STDOUT.sync = true
painter = Burrow::Client::TerrainPainter.new(ARGV.fetch(0))
collision_path = File.join(ARGV.fetch(0), "collision.bin")
activity = Burrow::MacActivity.new("Burrow Brigade landscape generation", precise: false)
STDIN.each_line do |line|
  begin
    activity.active = true
    job = JSON.parse(line)
    terrain = Burrow::Terrain.restore(job.fetch("terrain"))
    result = painter.render(terrain, job.fetch("biome"))
    # The GUI never inflates a mask to paint a placement preview. Its I/O thread
    # loads these already validated bytes after receiving this worker result.
    File.binwrite(collision_path, terrain.data)
    result[:collision] = {path: collision_path, seed: terrain.seed, width: terrain.width, height: terrain.height, revision: terrain.revision}
    puts JSON.generate(result)
  ensure
    activity.close
  end
end
