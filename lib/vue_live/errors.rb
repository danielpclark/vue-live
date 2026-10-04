# frozen_string_literal: true

module VueLive
  class Error < StandardError; end

  # Raised when a .vue file cannot be turned into a JavaScript module.
  class CompileError < Error
    attr_reader :file

    def initialize(message, file: nil)
      @file = file
      super(file ? "#{file}: #{message}" : message)
    end
  end

  # Raised when a component uses a feature the selected compiler backend cannot handle
  # (for example <script setup> with the pure Ruby backend).
  class UnsupportedFeature < CompileError; end

  # Raised when a requested path escapes the component root or has a disallowed extension.
  class ForbiddenPath < Error; end
end
