# ContainerEnv

A thread-safe Ruby wrapper around `ENV` that adds Docker secrets support and optional caching.

## Features

- **Docker secrets** — transparently reads secrets from files via the `KEY_FILE` convention
- **Optional caching** — configurable TTL (default 10 minutes) to avoid repeated file reads
- **Thread safe** — all state protected by a `Mutex`
- **Familiar API** — mirrors `Hash#fetch` semantics, raises `KeyError` on missing keys

## Requirements

Ruby 3.3+

## Installation

Add to your `Gemfile`:

```ruby
gem 'container_env'
```

Or install directly:

```sh
gem install container_env
```

## Usage

### Basic lookup

```ruby
require 'container_env'

# Raises KeyError if the key is not set
ContainerEnv.fetch('DATABASE_URL')

# Returns a default value instead of raising
ContainerEnv.fetch('DATABASE_URL', 'postgres://localhost/myapp')

# Calls the block instead of raising
ContainerEnv.fetch('DATABASE_URL') { |key| "default for #{key}" }

# [] also raises KeyError on missing keys (unlike ENV[] which returns nil)
ContainerEnv['DATABASE_URL']
```

### Docker secrets

When a key is not found in `ENV`, ContainerEnv checks for a companion `KEY_FILE` variable.
If present, it reads the secret from the file at that path and returns its contents (trailing newline stripped).

```sh
# Instead of DATABASE_URL=postgres://user:pass@host/db
# Docker injects the secret path:
DATABASE_URL_FILE=/run/secrets/database_url
```

```ruby
ContainerEnv.fetch('DATABASE_URL')
# => reads /run/secrets/database_url and returns its contents
```

This matches the [Docker secrets](https://docs.docker.com/engine/swarm/secrets/) convention and works with
Docker Swarm, Compose (`secrets:`), and Kubernetes (`secretKeyRef` mounted as files).

**Lookup order:** `ENV[key]` → `ENV["#{key}_FILE"]` (file read) → default / block / `KeyError`

### Caching

Caching is disabled by default. Enable it to avoid repeated file reads in hot paths:

```ruby
ContainerEnv.configure do |config|
  config.cache_enabled = true
  config.cache_ttl     = 600  # seconds, default is 600 (10 minutes)
end
```

Cached values are stored in-process with a monotonic TTL. The cache is shared across threads.

To clear the cache and reset configuration (useful in tests):

```ruby
ContainerEnv.reset!
```

### Inspecting configuration

```ruby
ContainerEnv.configuration.cache_enabled?  # => true/false
ContainerEnv.configuration.cache_ttl       # => Integer (seconds)
```

## Testing

In tests, inject a plain hash instead of `ENV` via `ContainerEnv::Fetcher` directly:

```ruby
fetcher = ContainerEnv::Fetcher.new(
  env:    { 'DATABASE_URL' => 'postgres://localhost/test' },
  cache:  ContainerEnv::Cache.new(ttl: 600),
  config: ContainerEnv::Configuration.new
)

fetcher.fetch('DATABASE_URL')  # => 'postgres://localhost/test'
```

Or call `ContainerEnv.reset!` in an `after` hook to clear cached state between examples:

```ruby
RSpec.configure do |config|
  config.after { ContainerEnv.reset! }
end
```

### Using with ClimateControl

[ClimateControl](https://github.com/thoughtbot/climate_control) modifies `ENV` in-place, which ContainerEnv reads
through transparently. **With caching disabled (the default) there is no incompatibility.**

With caching enabled, ContainerEnv may serve a stale cached value inside a `ClimateControl.modify` block, or leak
a test value set inside the block into the next lookup after it. Fix this with `clear_cache!`, which clears
the cache without touching configuration:

```ruby
RSpec.configure do |config|
  config.after { ContainerEnv.clear_cache! }
end
```

`clear_cache!` is a no-op when caching is disabled, so it is safe to add unconditionally.

## RuboCop integration

The gem ships a `ContainerEnv/PreferContainerEnv` cop that flags direct `ENV` reads and autocorrects them to `ContainerEnv`.

```ruby
# bad — flagged
ENV['DATABASE_URL']
ENV.fetch('DATABASE_URL', 'postgres://localhost/dev')
ENV.fetch('DATABASE_URL') { |k| "default for #{k}" }

# good — autocorrected to
ContainerEnv['DATABASE_URL']
ContainerEnv.fetch('DATABASE_URL', 'postgres://localhost/dev')
ContainerEnv.fetch('DATABASE_URL') { |k| "default for #{k}" }
```

Write access (`ENV[]=`) and enumeration methods (`to_h`, `each`, `replace`, …) are intentionally not flagged — they have no `ContainerEnv` equivalent and are commonly used in test setup.

### Enabling the cop

Add to your project's `.rubocop.yml`:

```yaml
require:
  - container_env/rubocop_extension

ContainerEnv/PreferContainerEnv:
  Enabled: true
```

Run rubocop as usual — offenses are autocorrectable with `-a`.

## Development

```sh
bundle install
bundle exec rspec       # run tests
bundle exec rubocop     # lint
```

## License

MIT
