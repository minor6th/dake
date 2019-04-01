require "dake/version"
require 'dake/parser'
require 'dake/analyzer'
require 'dake/executor'
require 'dake/protocol'
require 'dake/scheme'
require 'dake/resolver'
require 'dake/database'

module Dake
  class Error < StandardError; end
  TargetOption = Struct.new(:tag, :regex, :build_mode, :tree_mode)
end
