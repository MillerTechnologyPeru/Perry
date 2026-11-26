#!/usr/bin/env ruby
# Downloads the bottles and casks in a lock (Scripts/homebrew/resolve.rb)
# into a cache, as <cache>/<sha256>, and refuses any file whose hash doesn't
# match. Bottles are anonymous pulls from ghcr.io with the bearer token
# Homebrew itself sends; casks come from their vendors' URLs.
#
# Usage: ruby Scripts/homebrew/fetch.rb [--lock FILE] [--cache DIR]
#
# Uses only Ruby's standard library.

require "digest"
require "fileutils"
require "json"
require "net/http"
require "optparse"

ROOT = File.expand_path("../..", __dir__)
options = {
  lock: File.join(ROOT, "Tests/Homebrew/homebrew.lock.json"),
  cache: File.join(ROOT, ".build/homebrew/cache")
}
OptionParser.new do |o|
  o.on("--lock FILE") { |f| options[:lock] = f }
  o.on("--cache DIR") { |d| options[:cache] = d }
end.parse!

# Writes the response to a file, following redirects (ghcr sends blobs to
# its CDN, which doesn't take the token).
def download(url, path, token, redirects = 5)
  uri = URI(url)
  Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}" if token
    http.request(request) do |response|
      case response
      when Net::HTTPSuccess
        File.open(path, "wb") { |f| response.read_body { |chunk| f.write(chunk) } }
        return
      when Net::HTTPRedirection
        raise "too many redirects" if redirects == 0
        return download(URI.join(url, response["location"]).to_s, path, nil, redirects - 1)
      else
        raise "HTTP #{response.code}"
      end
    end
  end
end

lock = JSON.parse(File.read(options[:lock]))
FileUtils.mkdir_p(options[:cache])
failed = []
downloads = lock["formulae"].map { |name, entry| [name, entry, "QQ=="] } +
            lock.fetch("casks", {}).map { |name, entry| ["#{name} (cask)", entry, nil] }
downloads.each do |name, entry, token|
  cached = File.join(options[:cache], entry["sha256"])
  if File.exist?(cached)
    next if Digest::SHA256.file(cached).hexdigest == entry["sha256"]
    File.delete(cached)
  end
  partial = "#{cached}.partial"
  attempt = 0
  begin
    attempt += 1
    download(entry["url"], partial, token)
    actual = Digest::SHA256.file(partial).hexdigest
    raise "SHA-256 is #{actual}" unless actual == entry["sha256"]
    File.rename(partial, cached)
    puts "#{name} #{entry["version"]}"
  rescue StandardError => e
    File.delete(partial) if File.exist?(partial)
    if attempt < 3 && !e.message.start_with?("SHA-256")
      sleep 2**attempt
      retry
    end
    warn "fetch: #{name}: #{e.message}"
    failed << name
  end
end
abort "fetch: failed: #{failed.join(" ")}" unless failed.empty?
