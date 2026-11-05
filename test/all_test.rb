require 'minitest/autorun'
require_relative 'support'
Dir[File.join(__dir__, '*_test.rb')].sort.each do |path|
  require path unless path == __FILE__
end
