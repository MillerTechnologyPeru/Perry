#!/usr/bin/env ruby
# Picks the Homebrew formulae Perry is tested against and writes a lock:
# each one's version, bottle URL and SHA-256, and its runtime dependencies,
# from https://formulae.brew.sh/api (docs/homebrew-testing.md).
#
# Usage: ruby Scripts/homebrew/resolve.rb [--top N] [--tag TAG] [--out FILE] [--cask TOKEN]... [NAME...]
#
# Without names, takes the N most installed formulae (default: those that
# Tests/Homebrew/formulae.yml has tests for). A formula is left out when it
# has no bottle for TAG (default arm64_tahoe), has a service, or depends on
# one that doesn't qualify. Each --cask adds a cask to the lock's "casks":
# its version, download URL and SHA-256, the container's extension and the
# apps and binaries it installs; without --cask, the casks already in the
# output file stay. Uses only Ruby's standard library.

require "json"
require "net/http"
require "optparse"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
API = "https://formulae.brew.sh/api"

options = { tag: "arm64_tahoe", top: nil, casks: [], out: File.join(ROOT, "Tests/Homebrew/homebrew.lock.json") }
OptionParser.new do |o|
  o.on("--top N", Integer) { |n| options[:top] = n }
  o.on("--tag TAG") { |t| options[:tag] = t }
  o.on("--out FILE") { |f| options[:out] = f }
  o.on("--cask TOKEN") { |t| options[:casks] << t }
end.parse!

def get_json(path)
  uri = URI("#{API}/#{path}")
  3.times do |attempt|
    begin
      response = Net::HTTP.get_response(uri)
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
    rescue SocketError, Timeout::Error, JSON::ParserError
      nil
    end
    sleep 2**attempt
  end
  abort "resolve: cannot read #{uri}"
end

tag = options[:tag]
formulae = {}
get_json("formula.json").each { |f| formulae[f["name"]] = f }

# The bottle for the tag, or the one that fits every system.
def bottle(formula, tag)
  files = formula.dig("bottle", "stable", "files") or return nil
  files[tag] || files["all"]
end

usable = {}
formulae.each do |name, f|
  next if f["service"] || f["disabled"] || f["deprecated"]
  next unless bottle(f, tag)
  usable[name] = f
end

# Drops what depends on a formula that can't be poured.
loop do
  dropped = usable.keys.select { |n| usable[n]["dependencies"].any? { |d| !usable.key?(d) } }
  break if dropped.empty?
  dropped.each { |n| usable.delete(n) }
end

requested = ARGV.dup
if requested.empty?
  if options[:top]
    ranked = get_json("analytics/install-on-request/30d.json")["items"].map { |i| i["formula"] }
    requested = ranked.select { |n| usable.key?(n) }.first(options[:top])
  else
    requested = YAML.load(File.read(File.join(ROOT, "Tests/Homebrew/formulae.yml"), encoding: "UTF-8")).keys
  end
end
requested.each { |n| abort "resolve: #{n} has no usable #{tag} bottle" unless usable.key?(n) }

closure = {}
visit = lambda do |name|
  next if closure.key?(name)
  closure[name] = usable.fetch(name)
  closure[name]["dependencies"].each { |d| visit.call(d) }
end
requested.each { |n| visit.call(n) }

entries = {}
closure.keys.sort.each do |name|
  f = closure[name]
  b = bottle(f, tag)
  version = f["versions"]["stable"]
  version += "_#{f["revision"]}" if f["revision"].to_i > 0
  entries[name] = {
    "version" => version,
    "tag" => (f.dig("bottle", "stable", "files").key?(tag) ? tag : "all"),
    "url" => b["url"],
    "sha256" => b["sha256"],
    "dependencies" => f["dependencies"].sort
  }
end

# A cask's download, which a vendor serves: pinned by the SHA-256 the API
# gives, so a cask with :no_check has none to pin.
casks = options[:casks].empty? && File.exist?(options[:out]) ? JSON.parse(File.read(options[:out])).fetch("casks", {}) : {}
options[:casks].sort.each do |token|
  c = get_json("cask/#{token}.json")
  abort "resolve: #{token} is disabled or deprecated" if c["disabled"] || c["deprecated"]
  abort "resolve: #{token} has no SHA-256 to pin" unless c["sha256"] =~ /\A\h{64}\z/
  artifacts = c["artifacts"].flat_map { |a| a.is_a?(Hash) ? a.to_a : [] }
  casks[token] = {
    "version" => c["version"],
    "url" => c["url"],
    "sha256" => c["sha256"],
    "container" => File.basename(URI(c["url"]).path)[/\.(tar\.\w+|t\w+|\w+)\z/, 1],
    "apps" => artifacts.select { |k, _| k == "app" }.flat_map { |_, v| v.grep(String) },
    "binaries" => artifacts.select { |k, _| k == "binary" }.flat_map { |_, v| v.grep(String) }
  }
end

lock = { "tag" => tag, "requested" => requested.sort, "formulae" => entries }
lock["casks"] = casks.sort.to_h unless casks.empty?
File.write(options[:out], JSON.pretty_generate(lock) + "\n")
puts "#{options[:out]}: #{requested.size} requested, #{entries.size} with dependencies, #{casks.size} casks"
