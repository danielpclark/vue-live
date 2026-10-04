# frozen_string_literal: true

# `require 'vue_live/tasks'` in a Rakefile outside Rails to get the vue_live:* tasks.
require_relative '../vue_live'
load File.expand_path('tasks.rake', __dir__)
