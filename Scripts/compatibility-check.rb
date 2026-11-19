#!/usr/bin/env ruby
# Checks the compatibility database in docs/_apps.
#
# Usage: ruby Scripts/compatibility-check.rb
#
# Exits non-zero, naming the file, when an app file breaks the format that
# docs/contributing.md describes. Uses only Ruby's standard library.

require "yaml"
require "date"

ROOT = File.expand_path("..", __dir__)
DOCS = File.join(ROOT, "docs")
APPS = File.join(DOCS, "_apps")

APP_KEYS = %w[name platform kind developer reports].freeze
APP_REQUIRED = %w[name platform kind reports].freeze
REPORT_KEYS = %w[pr date perry arch app_version host level source notes screenshots].freeze
REPORT_REQUIRED = %w[pr date perry level source notes].freeze
SCREENSHOT_KEYS = %w[url caption].freeze

PLATFORMS = %w[ios macos catalyst].freeze
KINDS = %w[app game].freeze
ARCHS = %w[arm64 armv7 armv6 x86_64 i386].freeze
SOURCES = %w[title body screenshot].freeze

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

def slug(name)
  name.downcase.delete("'’.").tr("&", " ").gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
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

def check_report(file, where, report, urls)
  return unless check_keys(file, where, report, REPORT_KEYS, REPORT_REQUIRED)

  pr = report["pr"]
  error(file, "#{where} 'pr' is not a positive integer") unless pr.nil? || (pr.is_a?(Integer) && pr.positive?)
  date = report["date"]
  error(file, "#{where} 'date' is not a date") unless date.nil? || date.is_a?(Date)
  perry = report["perry"]
  error(file, "#{where} 'perry' is not a quoted string of 8 hexadecimal characters") unless perry.nil? || (perry.is_a?(String) && perry.match?(/\A[0-9a-f]{8}\z/))
  if report.key?("arch") && !ARCHS.include?(report["arch"])
    error(file, "#{where} 'arch' is not one of #{ARCHS.join(", ")}")
  end
  if report.key?("app_version") && !report["app_version"].is_a?(String)
    error(file, "#{where} 'app_version' is not a quoted string")
  end
  if report.key?("host") && !report["host"].is_a?(String)
    error(file, "#{where} 'host' is not a string")
  end
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

def check_app(file, urls, names)
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

  name = data["name"]
  if name.is_a?(String)
    expected = slug(name)
    error(file, "file name should be #{expected}.md for '#{name}'") unless File.basename(file, ".md") == expected
    if names.key?(name)
      error(file, "'#{name}' is also the name in #{names[name]}")
    else
      names[name] = file.sub("#{ROOT}/", "")
    end
  else
    error(file, "'name' is not a string")
  end
  error(file, "'platform' is not one of #{PLATFORMS.join(", ")}") unless data["platform"].nil? || PLATFORMS.include?(data["platform"])
  error(file, "'kind' is not one of #{KINDS.join(", ")}") unless data["kind"].nil? || KINDS.include?(data["kind"])
  error(file, "'developer' is not a string") if data.key?("developer") && !data["developer"].is_a?(String)

  reports = data["reports"]
  return 0 if reports.nil?
  unless reports.is_a?(Array) && !reports.empty?
    error(file, "'reports' is not a list with at least one report")
    return 0
  end
  reports.each_with_index { |report, i| check_report(file, "report #{i + 1}", report, urls) }

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

files = Dir.glob(File.join(APPS, "*")).sort
urls = {}
names = {}
report_count = 0
files.each do |file|
  if File.extname(file) != ".md"
    error(file, "is not a Markdown file")
    next
  end
  report_count += check_app(file, urls, names)
end
check_docs_files

if $errors.empty?
  puts "#{files.size} apps, #{report_count} reports"
else
  warn $errors
  warn "#{$errors.size} problem#{$errors.size == 1 ? "" : "s"} found"
  exit 1
end
