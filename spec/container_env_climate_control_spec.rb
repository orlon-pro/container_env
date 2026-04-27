# frozen_string_literal: true

require 'spec_helper'

# ClimateControl (https://github.com/thoughtbot/climate_control) modifies ENV
# in-place via ENV[]= and restores the original values after its block.
# It exposes no hooks, so ContainerEnv cannot observe ENV changes automatically.
#
# These specs simulate that behaviour directly — from ContainerEnv's perspective
# the mechanics are identical to using the real gem.
RSpec.describe ContainerEnv do # ClimateControl compatibility
  # Simulate ClimateControl.modify: sets keys in-place, yields, then restores.
  def with_env(overrides)
    old = overrides.keys.to_h { |k| [k.to_s, ENV.fetch(k.to_s, nil)] }
    overrides.each { |k, v| ENV[k.to_s] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  around do |example|
    original = ENV.to_h
    example.run
    ENV.replace(original)
    described_class.reset!
  end

  context 'with caching disabled (default)' do
    it 'sees the overridden value inside the block' do
      ENV['SERVICE_URL'] = 'https://production.example.com'

      with_env('SERVICE_URL' => 'https://test.example.com') do
        expect(described_class.fetch('SERVICE_URL')).to eq('https://test.example.com')
      end
    end

    it 'sees the restored value after the block' do
      ENV['SERVICE_URL'] = 'https://production.example.com'

      with_env('SERVICE_URL' => 'https://test.example.com') { nil }

      expect(described_class.fetch('SERVICE_URL')).to eq('https://production.example.com')
    end

    it 'raises KeyError for a key that only exists inside the block, once restored' do
      with_env('EPHEMERAL_KEY' => 'only-inside') { nil }

      expect { described_class.fetch('EPHEMERAL_KEY') }.to raise_error(KeyError)
    end
  end

  context 'with caching enabled' do
    before do
      described_class.configure do |c|
        c.cache_enabled = true
        c.cache_ttl     = 600
      end
    end

    it 'returns a stale cached value inside the block without cache clearing' do
      ENV['SERVICE_URL'] = 'https://production.example.com'
      described_class.fetch('SERVICE_URL') # warms the cache

      with_env('SERVICE_URL' => 'https://test.example.com') do
        # Cache was populated before the block — stale value is returned.
        expect(described_class.fetch('SERVICE_URL')).to eq('https://production.example.com')
      end
    end

    it 'sees the overridden value when the cache is cleared before the block' do
      ENV['SERVICE_URL'] = 'https://production.example.com'
      described_class.fetch('SERVICE_URL') # warms the cache

      described_class.clear_cache!

      with_env('SERVICE_URL' => 'https://test.example.com') do
        expect(described_class.fetch('SERVICE_URL')).to eq('https://test.example.com')
      end
    end

    it 'sees the restored value after the block when the cache is cleared on exit' do
      ENV['SERVICE_URL'] = 'https://production.example.com'

      with_env('SERVICE_URL' => 'https://test.example.com') do
        described_class.fetch('SERVICE_URL') # caches the test value
      end

      # Without clearing, the stale test value would be returned.
      described_class.clear_cache!

      expect(described_class.fetch('SERVICE_URL')).to eq('https://production.example.com')
    end

    it 'clear_cache! does not affect configuration' do
      described_class.clear_cache!

      expect(described_class.configuration.cache_enabled?).to be true
      expect(described_class.configuration.cache_ttl).to eq(600)
    end
  end

  context 'with the recommended after-hook (clear_cache! after each example)' do
    # The correct after-hook pattern for projects using both gems:
    #
    #   RSpec.configure do |config|
    #     config.after { ContainerEnv.clear_cache! }
    #   end
    #
    # The spec below verifies that this pattern eliminates stale-cache problems.

    before do
      described_class.configure { |c| c.cache_enabled = true }
    end

    after { described_class.clear_cache! }

    it 'does not leak cached values across examples (example 1 of 2)' do
      ENV['SHARED_KEY'] = 'first'
      expect(described_class.fetch('SHARED_KEY')).to eq('first')
    end

    it 'does not leak cached values across examples (example 2 of 2)' do
      ENV['SHARED_KEY'] = 'second'
      # Would return 'first' if clear_cache! were not called between examples.
      expect(described_class.fetch('SHARED_KEY')).to eq('second')
    end
  end
end
