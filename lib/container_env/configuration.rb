# frozen_string_literal: true

module ContainerEnv
  # :nodoc:
  class Configuration
    DEFAULT_TTL = 600
    DEFAULT_MAX_SIZE = 256

    attr_reader :cache_ttl, :cache_max_size
    attr_writer :cache_enabled

    def initialize
      @cache_enabled = false
      @cache_ttl = DEFAULT_TTL
      @cache_max_size = DEFAULT_MAX_SIZE
    end

    def cache_enabled?
      @cache_enabled
    end

    def cache_ttl=(seconds)
      @cache_ttl = Integer(seconds)
    end

    def cache_max_size=(size)
      @cache_max_size = Integer(size)
    end
  end
end
