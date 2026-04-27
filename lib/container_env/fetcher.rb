# frozen_string_literal: true

module ContainerEnv
  # :nodoc:
  class Fetcher
    SENTINEL = Object.new.freeze

    def initialize(cache:, config:, env: ENV)
      @env = env
      @cache = cache
      @config = config
    end

    # Reads cache_enabled? once to avoid a double call (#8).
    # Delegates to Cache#fetch_or_store when caching is on, which narrows
    # the stampede window compared to separate get/lookup/set calls (#3).
    def fetch(key, default = SENTINEL, &)
      key = key.to_s
      value = if @config.cache_enabled?
                @cache.fetch_or_store(key) { lookup(key) }
              else
                lookup(key)
              end
      return value unless value.nil?

      resolve_missing(key, default, &)
    end

    def [](key)
      fetch(key)
    end

    private

    def resolve_missing(key, default, &block)
      return block.call(key) if block
      return default unless default.equal?(SENTINEL)

      raise KeyError, "key not found: #{key.inspect}"
    end

    def lookup(key)
      return @env[key] if @env.key?(key)

      file_key = "#{key}_FILE"
      if @env.key?(file_key)
        path = @env[file_key]
        return ::File.read(path).chomp if ::File.readable?(path)
      end

      nil
    end
  end
end
