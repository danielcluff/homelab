#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"

scan_root = ARGV.fetch(0, ".trivy-rendered")
container_keys = %w[containers initContainers ephemeralContainers].freeze
images = []

walk = lambda do |value|
  case value
  when Hash
    value.each do |key, child|
      if container_keys.include?(key.to_s) && child.is_a?(Array)
        child.each do |container|
          image = container["image"] if container.is_a?(Hash)
          images << image if image.is_a?(String) && !image.empty?
        end
      end
      walk.call(child)
    end
  when Array
    value.each { |child| walk.call(child) }
  end
end

Dir.glob(File.join(scan_root, "**", "*.{yaml,yml,json}")).sort.each do |path|
  begin
    YAML.load_stream(File.read(path)).compact.each { |document| walk.call(document) }
  rescue Psych::SyntaxError => error
    warn "could not parse #{path}: #{error.message}"
    exit 1
  end
end

puts images.uniq.sort
