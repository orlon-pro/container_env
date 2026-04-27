# frozen_string_literal: true

module ContainerEnv
  # :nodoc:
  class Cache
    Entry = Data.define(:value, :cached_at)

    def initialize(ttl:, max_size: Configuration::DEFAULT_MAX_SIZE)
      @ttl = ttl
      @max_size = max_size
      @store = {}
      @mutex = build_mutex # fiber-aware when Async::Mutex is available (#4)
    end

    def get(key)
      @mutex.synchronize { read_entry(key) }
    end

    def set(key, value)
      @mutex.synchronize { write_entry(key, value) }
      value
    end

    # Atomic check-compute-store (#3).
    #
    # Calls the block only on a cache miss, then re-checks under the write lock
    # before storing. This narrows the stampede window: concurrent threads may
    # still compute in parallel, but only the first writer wins; the rest discard
    # their computed value and return what was stored. Nil values are never cached.
    def fetch_or_store(key)
      hit = get(key)
      return hit unless hit.nil?

      computed = yield
      return nil if computed.nil?

      @mutex.synchronize do
        current = read_entry(key)
        current.nil? ? write_entry(key, computed) : current
      end
    end

    def clear
      @mutex.synchronize { @store.clear }
    end

    private

    def read_entry(key)
      entry = @store[key]
      entry && !expired?(entry) ? entry.value : nil
    end

    # Deletes before inserting to refresh the key's insertion order,
    # then evicts the oldest entry when max_size is exceeded (#6).
    def write_entry(key, value)
      @store.delete(key)
      @store[key] = Entry.new(value: value, cached_at: clock)
      @store.shift while @store.size > @max_size
      value
    end

    def expired?(entry)
      clock - entry.cached_at > @ttl
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def build_mutex
      defined?(Async::Mutex) ? Async::Mutex.new : ::Mutex.new
    end
  end
end
