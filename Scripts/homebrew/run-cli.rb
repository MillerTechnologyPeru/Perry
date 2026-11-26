#!/usr/bin/env ruby
# Runs the tests in Tests/Homebrew/formulae.yml on the programs of a Homebrew
# prefix, and compares each one's stdout and exit status with the golden a Mac
# recorded.
#
# Record, on a Mac with the locked formulae installed by brew:
#   ruby Scripts/homebrew/run-cli.rb --record --bin "$(brew --prefix)/bin"
# Compare, under Perry, on a prefix poured by Scripts/homebrew/pour.rb:
#   ruby Scripts/homebrew/run-cli.rb --runner perry
#
# Each test runs in a new directory with its own HOME and PERRY_CONTAINER, the
# C locale, a timeout and PERRY_CRASH_REPORT=1. The rest of the environment passes
# through, so a caller sets LD_PRELOAD=libPerryExecShim.so and PERRY_LOADER.
# Uses only Ruby's standard library.

require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("../..", __dir__)
options = {
  tests: File.join(ROOT, "Tests/Homebrew/formulae.yml"),
  lock: File.join(ROOT, "Tests/Homebrew/homebrew.lock.json"),
  goldens: File.join(ROOT, "Tests/Homebrew/goldens"),
  bin: File.join(ROOT, ".build/homebrew/prefix/bin"),
  runner: [],
  timeout: 60,
  record: false,
  results: nil,
  only: []
}
OptionParser.new do |o|
  o.on("--record") { options[:record] = true }
  o.on("--bin DIR") { |d| options[:bin] = d }
  o.on("--runner COMMAND") { |c| options[:runner] = c.split.each_with_index.map { |w, i| i.zero? && File.exist?(w) ? File.expand_path(w) : w } }
  o.on("--goldens DIR") { |d| options[:goldens] = d }
  o.on("--timeout SECONDS", Integer) { |t| options[:timeout] = t }
  o.on("--results FILE") { |f| options[:results] = f }
  o.on("--formula NAME") { |n| options[:only] << n }
end.parse!

# Output as UTF-8 text, with bytes that aren't replaced, so it can go in JSON.
def clean(output)
  output.dup.force_encoding("UTF-8").scrub
end

# Runs one program, killing it at the deadline. Returns stdout, stderr and
# the exit status (128 + the signal, or "timeout").
def execute(command, stdin, directory, timeout)
  environment = {
    "HOME" => File.join(directory, "home"),
    "PERRY_CONTAINER" => File.join(directory, "container"),
    "PERRY_CRASH_REPORT" => "1",
    # The C locale, so output doesn't depend on the machine that runs it.
    "LC_ALL" => "C",
    "LANG" => "C"
  }
  FileUtils.mkdir_p([environment["HOME"], environment["PERRY_CONTAINER"]])
  Open3.popen3(environment, *command, chdir: directory, pgroup: true) do |i, o, e, thread|
    writer = Thread.new { (i.write(stdin) if stdin) rescue nil; i.close rescue nil }
    out = Thread.new { o.read }
    err = Thread.new { e.read }
    unless thread.join(timeout)
      Process.kill("KILL", -thread.pid) rescue nil
      thread.join
      return [clean(out.value), clean(err.value), "timeout"]
    end
    writer.join
    status = thread.value
    code = status.exitstatus || (128 + status.termsig)
    [clean(out.value), clean(err.value), code]
  end
end

lock = JSON.parse(File.read(options[:lock]))
tests = YAML.load(File.read(options[:tests], encoding: "UTF-8"))
names = tests.keys.select { |n| lock["requested"].include?(n) }
names &= options[:only] unless options[:only].empty?
FileUtils.mkdir_p(options[:goldens]) if options[:record]

results = []
names.each do |name|
  tests[name].each_with_index do |test, index|
    id = "#{name}-#{index}"
    command = test["command"] || name
    program = File.join(options[:bin], command)
    started = Time.now
    outcome, detail = nil
    Dir.mktmpdir("perry-homebrew") do |directory|
      (test["files"] || {}).each do |file, text|
        FileUtils.mkdir_p(File.dirname(File.join(directory, file)))
        File.write(File.join(directory, file), text)
      end
      stdout, stderr, status = execute(options[:runner] + [program] + (test["args"] || []).map(&:to_s), test["stdin"], directory, options[:timeout])
      golden = File.join(options[:goldens], "#{id}.json")
      if options[:record]
        File.write(golden, JSON.pretty_generate("stdout" => stdout, "status" => status) + "\n")
        outcome = "recorded"
      elsif !File.exist?(golden)
        outcome, detail = "skipped", "no golden"
      else
        expected = JSON.parse(File.read(golden))
        if status != expected["status"]
          outcome, detail = "failed", "exit status #{status}, expected #{expected["status"]}\n#{stderr}"
        elsif test["match"] && !Regexp.new(test["match"]).match?(stdout)
          outcome, detail = "failed", "stdout doesn't match #{test["match"]}:\n#{stdout}"
        elsif !test["match"] && !test["ignore_stdout"] && stdout != expected["stdout"]
          outcome, detail = "failed", "stdout differs:\n#{stdout}\nexpected:\n#{expected["stdout"]}"
        else
          outcome = "golden"
        end
      end
    end
    puts "#{outcome.ljust(8)} #{id}"
    puts detail.lines.map { |l| "         #{l}" }.join if detail && outcome == "failed"
    results << { "id" => id, "formula" => name, "result" => outcome, "detail" => detail, "seconds" => (Time.now - started).round(2) }
  end
end

File.write(options[:results], JSON.pretty_generate(results) + "\n") if options[:results]
failed = results.count { |r| r["result"] == "failed" }
puts "#{results.size} tests, #{failed} failed"
exit(failed.zero? ? 0 : 1)
