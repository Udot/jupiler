#!/usr/bin/env ruby

begin
  require 'pathname'
  base = Pathname(__FILE__).expand_path
  filename = base.to_s.split('/').last
  lib_path = base.to_s.gsub("/#{filename}",'')
  lib = lib_path + "/lib/git_lib.rb"
  require lib

  # kick start the thing :
  GitLib::Command.kickstart!(ARGV[0], ENV["SSH_ORIGINAL_COMMAND"])
rescue => e
  STDERR.puts "REMOTE: An error occured, please contact administrator."
  a = File.open(File.expand_path("../../../errors_sh", __FILE__), "a")
  a << Time.now
  a << " - "
  a << e
  a << "\n"
  a.close
end
