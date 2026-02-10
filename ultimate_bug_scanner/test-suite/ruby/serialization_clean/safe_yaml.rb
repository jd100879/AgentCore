# frozen_string_literal: true
require 'yaml'

path = ARGV[0] || 'payload.yml'
permitted = [String, Integer, Float, Array, Hash]
data = YAML.safe_load(File.read(path), permitted_classes: permitted, permitted_symbols: [], aliases: false)
puts data.inspect
