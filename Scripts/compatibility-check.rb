#!/usr/bin/env ruby
# Checks the compatibility database in docs/_apps.
#
# Usage: ruby Scripts/compatibility-check.rb
#
# Each app is docs/_apps/<platform>/<bundle id>.md. The script exits
# non-zero, naming the file, when an app file breaks the format that
# docs/contributing.md describes. Uses only Ruby's standard library.

require "yaml"
require "date"

ROOT = File.expand_path("..", __dir__)
DOCS = File.join(ROOT, "docs")
APPS = File.join(DOCS, "_apps")

APP_KEYS = %w[name bundle_id platform kind developer reports].freeze
APP_REQUIRED = %w[name bundle_id platform kind reports].freeze
REPORT_KEYS = %w[pr date perry platform cpu app_version hardware level source notes screenshots].freeze
REPORT_REQUIRED = %w[pr date perry platform cpu hardware level source notes].freeze
SCREENSHOT_KEYS = %w[url caption].freeze

# Darwin's platform names, and the CPUs a Mach-O for each can be built for.
PLATFORM_CPUS = {
  "ios" => %w[arm64 armv7 armv6],
  "macos" => %w[arm64 x86_64 i386],
  "maccatalyst" => %w[arm64 x86_64]
}.freeze
KINDS = %w[app game].freeze
SOURCES = %w[title body screenshot].freeze
BUNDLE_ID = /\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/

SCREENSHOT_URL = %r{\A(?:
  https://github\.com/user-attachments/assets/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
  |https://github\.com/MillerTechnologyPeru/Perry/assets/\d+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}
  |https://user-images\.githubusercontent\.com/\d+/[A-Za-z0-9._-]+
)\z}x

DOC_EXTENSIONS = %w[.md .yml .html .css].freeze
DOC_EXCEPTIONS = %w[Gemfile .gitignore].freeze
DOC_SKIPPED = %w[_site .jekyll-cache vendor .bundle].freeze

$errors = []

def error(file, message)
  $errors << "#{file.sub("#{ROOT}/", "")}: #{message}"
end

def check_keys(file, where, hash, allowed, required)
  unless hash.is_a?(Hash)
    error(file, "#{where} is not a mapping")
    return false
  end
  (hash.keys - allowed).each { |key| error(file, "#{where} has an unknown key '#{key}'") }
  required.each do |key|
    value = hash[key]
    error(file, "#{where} is missing '#{key}'") if value.nil? || (value.respond_to?(:empty?) && value.empty?)
  end
  true
end

def check_report(file, where, report, platform, urls)
  return unless check_keys(file, where, report, REPORT_KEYS, REPORT_REQUIRED)

  pr = report["pr"]
  error(file, "#{where} 'pr' is not a positive integer") unless pr.nil? || (pr.is_a?(Integer) && pr.positive?)
  date = report["date"]
  error(file, "#{where} 'date' is not a date") unless date.nil? || date.is_a?(Date)
  perry = report["perry"]
  error(file, "#{where} 'perry' is not a quoted string of 8 hexadecimal characters") unless perry.nil? || (perry.is_a?(String) && perry.match?(/\A[0-9a-f]{8}\z/))
  report_platform = report["platform"]
  if report_platform && report_platform != platform
    error(file, "#{where} 'platform' is #{report_platform}, but the file is under #{platform}/")
  end
  cpu = report["cpu"]
  cpus = PLATFORM_CPUS[platform]
  if cpu && cpus && !cpus.include?(cpu)
    error(file, "#{where} 'cpu' is not one of #{cpus.join(", ")} for #{platform}")
  end
  if report.key?("app_version") && !report["app_version"].is_a?(String)
    error(file, "#{where} 'app_version' is not a quoted string")
  end
  hardware = report["hardware"]
  error(file, "#{where} 'hardware' is not a string") unless hardware.nil? || hardware.is_a?(String)
  level = report["level"]
  error(file, "#{where} 'level' is not an integer from 1 to 5") unless level.nil? || (level.is_a?(Integer) && (1..5).cover?(level))
  source = report["source"]
  error(file, "#{where} 'source' is not one of #{SOURCES.join(", ")}") unless source.nil? || SOURCES.include?(source)
  notes = report["notes"]
  error(file, "#{where} 'notes' is not a string") unless notes.nil? || notes.is_a?(String)

  return unless report.key?("screenshots")
  shots = report["screenshots"]
  unless shots.is_a?(Array) && !shots.empty?
    error(file, "#{where} 'screenshots' is not a list")
    return
  end
  shots.each_with_index do |shot, j|
    shot_where = "#{where} screenshot #{j + 1}"
    next unless check_keys(file, shot_where, shot, SCREENSHOT_KEYS, SCREENSHOT_KEYS)
    url = shot["url"]
    next unless url.is_a?(String)
    error(file, "#{shot_where} 'url' is not a pull request attachment URL") unless url.match?(SCREENSHOT_URL)
    if urls.key?(url)
      error(file, "#{shot_where} 'url' also appears in #{urls[url]}")
    else
      urls[url] = file.sub("#{ROOT}/", "")
    end
  end
end

def check_app(file, urls)
  dir_platform = File.basename(File.dirname(file))
  unless PLATFORM_CPUS.key?(dir_platform)
    error(file, "is not under one of #{PLATFORM_CPUS.keys.map { |p| "#{p}/" }.join(", ")}")
    return 0
  end

  text = File.read(file, encoding: "UTF-8")
  match = text.match(/\A---\r?\n(.*?)\r?\n---\r?\n?/m)
  unless match
    error(file, "has no front matter")
    return 0
  end
  begin
    data = YAML.safe_load(match[1], permitted_classes: [Date])
  rescue Psych::Exception => e
    error(file, "front matter does not parse: #{e.message}")
    return 0
  end
  return 0 unless check_keys(file, "front matter", data, APP_KEYS, APP_REQUIRED)

  error(file, "'name' is not a string") if data.key?("name") && !data["name"].is_a?(String)
  bundle_id = data["bundle_id"]
  if bundle_id.is_a?(String)
    error(file, "'bundle_id' is not a reverse-DNS identifier") unless bundle_id.match?(BUNDLE_ID)
    error(file, "file name should be #{bundle_id}.md") unless File.basename(file, ".md") == bundle_id
  elsif !bundle_id.nil?
    error(file, "'bundle_id' is not a quoted string")
  end
  platform = data["platform"]
  if platform && platform != dir_platform
    error(file, "'platform' is #{platform}, but the file is under #{dir_platform}/")
  end
  error(file, "'kind' is not one of #{KINDS.join(", ")}") unless data["kind"].nil? || KINDS.include?(data["kind"])
  error(file, "'developer' is not a string") if data.key?("developer") && !data["developer"].is_a?(String)

  reports = data["reports"]
  return 0 if reports.nil?
  unless reports.is_a?(Array) && !reports.empty?
    error(file, "'reports' is not a list with at least one report")
    return 0
  end
  reports.each_with_index { |report, i| check_report(file, "report #{i + 1}", report, dir_platform, urls) }

  dates = reports.map { |report| report.is_a?(Hash) ? report["date"] : nil }
  if dates.all? { |date| date.is_a?(Date) } && dates.each_cons(2).any? { |a, b| b < a }
    error(file, "reports are not in date order, oldest first")
  end
  reports.size
end

def check_docs_files
  Dir.glob(File.join(DOCS, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
    next if File.directory?(path)
    relative = path.sub("#{DOCS}/", "")
    next if DOC_SKIPPED.any? { |dir| relative == dir || relative.start_with?("#{dir}/") }
    next if DOC_EXCEPTIONS.include?(relative) || relative == "Gemfile.lock"
    error(path, "has an extension other than #{DOC_EXTENSIONS.join(", ")}") unless DOC_EXTENSIONS.include?(File.extname(path))
  end
end

entries = Dir.glob(File.join(APPS, "**", "*")).reject { |path| File.directory?(path) }.sort
urls = {}
apps = 0
report_count = 0
entries.each do |file|
  relative = file.sub("#{APPS}/", "")
  if File.extname(file) != ".md" || relative.count("/") != 1
    error(file, "is not docs/_apps/<platform>/<bundle id>.md")
    next
  end
  apps += 1
  report_count += check_app(file, urls)
end
check_docs_files

if $errors.empty?
  puts "#{apps} apps, #{report_count} reports"
else
  warn $errors
  warn "#{$errors.size} problem#{$errors.size == 1 ? "" : "s"} found"
  exit 1
end
