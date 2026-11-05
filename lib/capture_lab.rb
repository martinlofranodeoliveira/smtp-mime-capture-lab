require 'json'
require 'socket'
require 'securerandom'
require 'thread'
require 'rbconfig'

module CaptureLab
  VERSION = '0.1.0'
  ROOT = File.expand_path('..', __dir__)

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  class Error < StandardError
    attr_reader :code, :smtp

    def initialize(code, smtp = 451)
      @code = code
      @smtp = smtp
      super(code)
    end
  end
end

require_relative 'capture_lab/limits'
require_relative 'capture_lab/wire'
require_relative 'capture_lab/mailbox'
require_relative 'capture_lab/process_runner'
require_relative 'capture_lab/inspector'
require_relative 'capture_lab/session'
require_relative 'capture_lab/server'
