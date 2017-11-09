#!/usr/bin/env ruby

# run on vm to gather up logs and only generate them for one type of worker

# for i in `grep ::Runner#g log/evm.log |sed 's/^[^(]*MIQ(\([^)]*\)::Runner#get_message_via_drb).*$/\1/' | sort | uniq| sort -nr` ; do ./tools/split_logs.rb --name $i ; done

require 'optparse'
require 'fileutils'
require 'date'

options = {:name => "MiqGenericWorker", :max => 200}
OptionParser.new do |opt|
  opt.banner = "Usage: split_logs.rb --name worker_name [log_file_names]"
  opt.on('-n', '--name=NAME',   String, "Name of process worer")  { |v| options[:name] = v }
  opt.on('-p', '--pid=PID',     String, "PID(s) for worker - comma separated") { |v| options[:pid]  = v }
  opt.on('-q', '--quick',               "Assume single pid")      { |v| options[:quick] = v }
  opt.on(      '--keep',                "Keep temp directory around") { |v| options[:keep] = v }
  opt.on('-f', '--force',               "Overwrite files and directories") { |v| options[:force] = v }
  opt.on('-c', '--check',               "Check file derivation") { |v| options[:check] = v }
  opt.on(      '--prefix NAME', String, "Prefix to use for target log files") { |v| options[:prefix] = v }
  opt.on(      '--max=COUNT',   Integer, "Max number of pids per file (default: 200)") { |v| options[:max]  = v }
  opt.parse!(ARGV)
end

# be verbose unless we're outputting to standardout
verbose = options[:prefix] != "-"

options[:name].gsub!("::Runner", "")
targetname = options[:prefix]
dirname = if options[:prefix] && options[:prefix] != "-"
            options[:prefix]
          else
            name = options[:name].split("::").last # ::Runner was already removed
            "tmp/" + name.gsub(/miq/i, '').gsub(/worker/i, '').downcase
          end
targetname ||= "#{dirname}"
targetname += ".tgz" unless targetname == "-" || targetname.include?("tgz")

if options[:check]
  puts "tn=#{targetname} dn=#{dirname}"
  exit 1
end

if targetname != "-" && File.exist?(targetname)
  STDERR.puts "target file #{targetname} exists"
  exit 1 unless options[:force]
end

if Dir.exist?(dirname)
  STDERR.puts "target directory #{dirname} exists"
  exit 1 unless options[:force]
else
  Dir.mkdir(dirname)
end

filenames = ARGV
filenames = Dir["log/evm.log*"] if filenames.empty?

pid_numbers = options[:pid]
# determine pids
if pid_numbers
  pid_numbers = pid_numbers.split(",").map(&:strip)
else
  pid_numbers = []
  full_process_name = "#{options[:name]}::Runner#get_message_via_drb"
  filenames.each do |filename|
    print "looking  for #{options[:name]} in #{filename}: " if verbose
    cat = filename =~ /\.gz$/ ? 'zcat' : 'cat'
    new_pids = `#{cat} #{filename} | grep '#{full_process_name}' | sed 's/^[^#]*#\\([0-9]*\\):.*/\\1/' | sort | uniq`.chomp.split("\n")
    if options[:max] && new_pids.size > options[:max]
      puts new_pids[0..10] if verbose
      STDERR.puts "ERROR: too many pids. Assuming there aren't really #{new_pids.size} pids - assuming error"
      exit 4
    end

    if new_pids.empty?
      puts "empty"
    else
      puts "#{new_pids.sort.join(", ")}" if verbose
      pid_numbers = (pid_numbers + new_pids).uniq
    end
    break if options[:quick] && !pid_numbers.empty?
  end
end

# puts "Process #{options[:name]} uses pids #{pid_numbers.sort.join ","}" if verbose

if pid_numbers.empty?
  STDERR.puts "No pids to process"
  exit 2
end

pid_rex = "\\(#{pid_numbers.map {|pid| "##{pid}:" }.join("\\|")}\\)"
# puts "pid_rex: #{pid_rex.to_s}" if verbose

filenames.each do |filename|
  target = File.basename(filename).gsub(/.gz$/,'')
  # do we need to let people know that the last day is partial (I had p in there for a while)
  target = "#{target}-#{(Date.today + 1).strftime("%Y%m%d")}" if target !~ /20/
  print "grepping #{filename} > #{target}  -- " if verbose
  cat = filename =~ /\.gz$/ ? 'zcat' : 'cat'
  `#{cat} #{filename} | grep '#{pid_rex}' > #{dirname}/#{target}`
  puts "#{`wc -l #{dirname}/#{target}`.chomp.split.first} times" if verbose
end

puts "creating #{targetname}" if verbose
`tar -czf #{targetname} #{dirname}`
FileUtils.rm_r("#{dirname}") unless options[:keep]

# grep 'Message id' $i | grep -v ', Delivering\.\.\.' > deliver-$i
# grep 'CACHE clear' $i | grep -v MiqRegion > cache-$i

