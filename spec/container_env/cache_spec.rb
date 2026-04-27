# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ContainerEnv::Cache do
  subject(:cache) { described_class.new(ttl: 600) }

  describe '#get and #set' do
    it 'returns nil for an unknown key' do
      expect(cache.get('MISSING')).to be_nil
    end

    it 'returns the stored value' do
      cache.set('KEY', 'value')
      expect(cache.get('KEY')).to eq('value')
    end

    it 'stores nil values and returns nil (treated as missing)' do
      cache.set('KEY', nil)
      expect(cache.get('KEY')).to be_nil
    end
  end

  describe '#fetch_or_store' do
    it 'computes and returns the value on a cache miss' do
      result = cache.fetch_or_store('KEY') { 'computed' }
      expect(result).to eq('computed')
    end

    it 'stores the computed value so subsequent gets hit the cache' do
      cache.fetch_or_store('KEY') { 'computed' }
      expect(cache.get('KEY')).to eq('computed')
    end

    it 'returns the cached value without calling the block on a hit' do
      cache.set('KEY', 'cached')
      calls = 0
      result = cache.fetch_or_store('KEY') do
        calls += 1
        'computed'
      end
      expect(result).to eq('cached')
      expect(calls).to eq(0)
    end

    it 'returns nil and does not cache when the block returns nil' do
      result = cache.fetch_or_store('KEY') { nil }
      expect(result).to be_nil
      expect(cache.get('KEY')).to be_nil
    end

    it 'handles concurrent misses without raising' do
      threads = 10.times.map do
        Thread.new { cache.fetch_or_store('KEY') { 'value' } }
      end
      results = threads.map(&:value)
      expect(results).to all(eq('value'))
    end
  end

  describe 'TTL expiry' do
    subject(:cache) { described_class.new(ttl: 0.01) }

    it 'returns nil after TTL has elapsed' do
      cache.set('KEY', 'value')
      sleep 0.02
      expect(cache.get('KEY')).to be_nil
    end

    it 'returns the value before TTL elapses' do
      cache.set('KEY', 'value')
      expect(cache.get('KEY')).to eq('value')
    end
  end

  describe 'max_size eviction' do
    subject(:cache) { described_class.new(ttl: 600, max_size: 3) }

    it 'evicts the oldest entry when max_size is exceeded' do
      cache.set('A', '1')
      cache.set('B', '2')
      cache.set('C', '3')
      cache.set('D', '4')
      expect(cache.get('A')).to be_nil
    end

    it 'keeps newer entries after eviction' do
      cache.set('A', '1')
      cache.set('B', '2')
      cache.set('C', '3')
      cache.set('D', '4')
      expect(cache.get('D')).to eq('4')
    end

    it 'does not evict when under max_size' do
      cache.set('A', '1')
      cache.set('B', '2')
      expect(cache.get('A')).to eq('1')
    end

    it 'refreshes insertion order on re-set, evicting the true oldest' do
      cache.set('A', '1')
      cache.set('B', '2')
      cache.set('A', 'refreshed') # A is now newest
      cache.set('C', '3')         # now at max_size=3: A, C are newest; B is oldest
      cache.set('D', '4')         # B should be evicted
      expect(cache.get('B')).to be_nil
      expect(cache.get('A')).to eq('refreshed')
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      cache.set('A', '1')
      cache.set('B', '2')
      cache.clear
      expect(cache.get('A')).to be_nil
      expect(cache.get('B')).to be_nil
    end
  end

  describe 'thread safety' do
    it 'handles concurrent writes without raising' do
      threads = 20.times.map do |i|
        Thread.new { cache.set("KEY_#{i}", "value_#{i}") }
      end
      expect { threads.each(&:join) }.not_to raise_error
    end

    it 'handles concurrent reads and writes without raising' do
      threads = 10.times.map { |i| Thread.new { cache.set("K#{i}", i.to_s) } } +
                10.times.map { |i| Thread.new { cache.get("K#{i}") } }
      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe 'fiber-aware mutex (#4)' do
    context 'when Async::Mutex is defined' do
      before { stub_const('Async::Mutex', Class.new(Mutex)) }

      it 'uses Async::Mutex internally' do
        instance = described_class.new(ttl: 600)
        expect(instance.instance_variable_get(:@mutex)).to be_a(Async::Mutex)
      end
    end

    context 'when Async::Mutex is not defined' do
      it 'uses ::Mutex internally' do
        expect(cache.instance_variable_get(:@mutex)).to be_a(Mutex)
      end
    end
  end
end
