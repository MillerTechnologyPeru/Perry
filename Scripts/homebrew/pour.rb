#!/usr/bin/env ruby
# Pours the bottles of a lock (Scripts/homebrew/resolve.rb), fetched by
# Scripts/homebrew/fetch.rb, into a Homebrew prefix: the Cellar, the opt
# links and bin. Then relocates them as brew does: the placeholders
# @@HOMEBREW_PREFIX@@ and @@HOMEBREW_CELLAR@@ become the prefix the programs
# will run under, in Mach-O load commands with install_name_tool and in text
# files with a plain replacement.
#
# Usage: ruby Scripts/homebrew/pour.rb [--lock FILE] [--cache DIR] [--prefix DIR] [--as PATH] [--sign]
#
# --prefix is where the files go (default .build/homebrew/prefix); --as is
# where the programs will see it (default /opt/homebrew, the prefix the
# Apple silicon bottles are built for), when a container mounts --prefix
# there. --sign ad-hoc signs each Mach-O after it changes, with codesign, so a
# Mac can run a prefix poured with --as set to --prefix (to record goldens
# from the locked bottles themselves). install_name_tool and otool come from the PATH, or from
# $INSTALL_NAME_TOOL and $OTOOL (cctools-port's, in Scripts/build-cctools.sh).
# Uses only Ruby's standard library.

require "fileutils"
require "find"
require "json"
require "open3"
require "optparse"

ROOT = File.expand_path("../..", __dir__)
options = {
  lock: File.join(ROOT, "Tests/Homebrew/homebrew.lock.json"),
  cache: File.join(ROOT, ".build/homebrew/cache"),
  prefix: File.join(ROOT, ".build/homebrew/prefix"),
  as: "/opt/homebrew"
}
OptionParser.new do |o|
  o.on("--lock FILE") { |f| options[:lock] = f }
  o.on("--cache DIR") { |d| options[:cache] = d }
  o.on("--prefix DIR") { |d| options[:prefix] = d }
  o.on("--as PATH") { |p| options[:as] = p }
  o.on("--sign") { options[:sign] = true }
end.parse!

INSTALL_NAME_TOOL = ENV["INSTALL_NAME_TOOL"] || "install_name_tool"
OTOOL = ENV["OTOOL"] || "otool"
PLACEHOLDERS = ["@@HOMEBREW_PREFIX@@", "@@HOMEBREW_CELLAR@@"].freeze
# 64-bit Mach-O of either byte order, and fat files (Java classes share
# the fat magic, and have no placeholders to find).
MACHO_MAGICS = ["\xCF\xFA\xED\xFE", "\xFE\xED\xFA\xCF", "\xCA\xFE\xBA\xBE", "\xBE\xBA\xFE\xCA"].map { |m| m.b }.freeze

def run(*command)
  output, status = Open3.capture2e(*command)
  abort "pour: #{command.join(" ")}: #{output}" unless status.success?
  output
end

def macho?(path)
  File.open(path, "rb") { |f| MACHO_MAGICS.include?(f.read(4)) }
rescue SystemCallError
  false
end

def relocate_text(string, prefix)
  string.gsub("@@HOMEBREW_PREFIX@@", prefix).gsub("@@HOMEBREW_CELLAR@@", "#{prefix}/Cellar")
end

# Rewrites the install names, dependencies and run paths of a Mach-O that
# name a placeholder.
def relocate_macho(path, prefix)
  libraries = run(OTOOL, "-L", path).lines.drop(1).map { |l| l.strip.sub(/ \(compatibility.*\)\z/, "") }
  commands = run(OTOOL, "-l", path).lines.map(&:strip)
  rpaths = commands.each_cons(3).select { |c| c[0] == "cmd LC_RPATH" }.map { |c| c[2][/\Apath (.*) \(offset \d+\)\z/, 1] }.compact
  id = commands.each_cons(3).find { |c| c[0] == "cmd LC_ID_DYLIB" }&.at(2)&.[](/\Aname (.*) \(offset \d+\)\z/, 1)
  arguments = []
  arguments += ["-id", relocate_text(id, prefix)] if id && id.include?("@@HOMEBREW")
  libraries.each do |l|
    next if l == id || !l.include?("@@HOMEBREW")
    arguments += ["-change", l, relocate_text(l, prefix)]
  end
  rpaths.each do |r|
    arguments += ["-rpath", r, relocate_text(r, prefix)] if r.include?("@@HOMEBREW")
  end
  return if arguments.empty?
  run(INSTALL_NAME_TOOL, *arguments, path)
end

lock = JSON.parse(File.read(options[:lock]))
root = options[:prefix]
cellar = File.join(root, "Cellar")
FileUtils.mkdir_p([File.join(root, "opt"), File.join(root, "bin")])

lock["formulae"].each do |name, entry|
  keg = File.join(cellar, name, entry["version"])
  archive = File.join(options[:cache], entry["sha256"])
  abort "pour: #{archive} is not fetched (Scripts/homebrew/fetch.rb)" unless File.exist?(archive)
  FileUtils.rm_rf(File.join(cellar, name))
  FileUtils.mkdir_p(cellar)
  # A bottle's top directory is <name>/<version>.
  run("tar", "-xzf", archive, "-C", cellar)
  abort "pour: #{name}'s bottle has no #{name}/#{entry["version"]}" unless File.directory?(keg)

  Find.find(keg) do |path|
    next unless File.file?(path) && !File.symlink?(path)
    if macho?(path)
      mode = File.stat(path).mode
      File.chmod(mode | 0o200, path)
      relocate_macho(path, options[:as])
      run("codesign", "--force", "--sign", "-", path) if options[:sign]
      File.chmod(mode, path)
    else
      contents = File.binread(path)
      next unless PLACEHOLDERS.any? { |p| contents.include?(p) }
      mode = File.stat(path).mode
      File.chmod(mode | 0o200, path)
      File.binwrite(path, relocate_text(contents, options[:as]))
      File.chmod(mode, path)
    end
  end

  link = File.join(root, "opt", name)
  FileUtils.rm_f(link)
  File.symlink("../Cellar/#{name}/#{entry["version"]}", link)
  %w[bin sbin].each do |dir|
    next unless File.directory?(File.join(keg, dir))
    Dir.children(File.join(keg, dir)).sort.each do |program|
      target = File.join(root, "bin", program)
      FileUtils.rm_f(target)
      File.symlink("../Cellar/#{name}/#{entry["version"]}/#{dir}/#{program}", target)
    end
  end
  puts "#{name} #{entry["version"]}"
end
