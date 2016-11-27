#!/usr/bin/env ruby

require './unicorn_process.rb'
processes = UnicornProcess.processes
processes.each { |process|
  puts "PID: #{process.pid}"
  puts "  directory: #{process.working_directory}"
  puts "       port: #{process.port.inspect}"
  puts "     worker: #{process.worker}"
}

