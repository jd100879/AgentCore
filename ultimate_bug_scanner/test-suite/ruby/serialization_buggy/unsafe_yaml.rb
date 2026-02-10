# frozen_string_literal: true
require 'yaml'

path = ARGV[0] || 'payload.yml'
data = YAML.load(File.read(path))
puts data.inspect
