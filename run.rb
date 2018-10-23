#!/usr/bin/env ruby
require_relative 'lib/decaf'

directory = ENV["DIRECTORY"]
raise "DIRECTORY env variable not defined" unless directory

files = Dir["#{directory}/**/*.rb"]
files.each do |filename|
  puts "Processing file: #{filename}"
  buffer = Parser::Source::Buffer.new('(string)')
  buffer.source = File.read(filename)
  begin
    ast = Parser::CurrentRuby.parse(buffer.source)
  rescue Parser::SyntaxError => error
    puts "couldn't read #{filename} skipped"
    next
  end
  rewriter = Decaf::Rewriter.new
  content = rewriter.rewrite(buffer, ast)
  File.write(filename, content)
end
puts "Done!"
