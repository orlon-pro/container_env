# frozen_string_literal: true

require_relative 'container_env/version'
require_relative 'container_env/configuration'
require_relative 'container_env/cache'
require_relative 'container_env/fetcher'

# ENV wrapper with Docker secrets support, optional caching, and thread safety.
module ContainerEnv
  # Plain stdlib Mutex used only to bootstrap @mutex itself (one-time, at startup).
  INIT_MUTEX = ::Mutex.new
  private_constant :INIT_MUTEX

  class << self
    def fetch(key, *, &)
      fetcher.fetch(key, *, &)
    end

    def [](key)
      fetcher[key]
    end

    # Yields configuration, then atomically rebuilds the cache and invalidates
    # the fetcher so next call picks up the new settings. Holds the mutex for
    # the entire block, preventing concurrent configuration reads mid-update (#5).
    def configure
      mutex.synchronize do
        @configuration ||= Configuration.new
        yield @configuration
        @cache = Cache.new(ttl: @configuration.cache_ttl, max_size: @configuration.cache_max_size)
        @fetcher = nil # force rebuild so it adopts the new cache (#1)
      end
      nil
    end

    def configuration
      mutex.synchronize { @configuration ||= Configuration.new }
    end

    def reset!
      mutex.synchronize do
        @configuration = nil
        @cache = nil
        @fetcher = nil
      end
    end

    # Clears cached values without touching configuration or the fetcher.
    # Use this in test after-hooks when pairing with ClimateControl (or any
    # other tool that modifies ENV in-place), so the next fetch sees the
    # restored ENV rather than a stale cached value.
    #
    #   RSpec.configure do |config|
    #     config.after { ContainerEnv.clear_cache! }
    #   end
    def clear_cache!
      mutex.synchronize { @cache&.clear }
    end

    private

    # Lazy, thread-safe mutex factory. Uses INIT_MUTEX only on the very first
    # call; after that the fast path avoids any locking (#2, #4).
    def mutex
      return @mutex if @mutex

      INIT_MUTEX.synchronize { @mutex ||= build_mutex }
    end

    # Returns a fiber-aware mutex when Async::Mutex is available (e.g. Falcon),
    # falling back to the stdlib Mutex for thread-based servers (#4).
    def build_mutex
      defined?(Async::Mutex) ? Async::Mutex.new : ::Mutex.new
    end

    # Fast path skips the mutex entirely once @fetcher is initialized (#2).
    # Worst case on JRuby/TruffleRuby: two Fetcher objects created, one discarded.
    def fetcher
      return @fetcher if @fetcher

      mutex.synchronize do
        @configuration ||= Configuration.new
        @cache ||= Cache.new(ttl: @configuration.cache_ttl, max_size: @configuration.cache_max_size)
        @fetcher ||= Fetcher.new(cache: @cache, config: @configuration)
      end
    end
  end
end
