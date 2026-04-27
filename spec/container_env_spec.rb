# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe ContainerEnv do
  around do |example|
    original = ENV.to_h
    example.run
    ENV.replace(original)
  end

  describe '.fetch' do
    it 'fetches a value from ENV' do
      ENV['TEST_KEY'] = 'hello'
      expect(described_class.fetch('TEST_KEY')).to eq('hello')
    end

    it 'raises KeyError for missing key with no default' do
      expect { described_class.fetch('TOTALLY_MISSING_XYZ') }.to raise_error(KeyError)
    end

    it 'returns the default for missing key' do
      expect(described_class.fetch('TOTALLY_MISSING_XYZ', 'default')).to eq('default')
    end

    it 'calls the block for missing key' do
      result = described_class.fetch('TOTALLY_MISSING_XYZ') { |k| "block_#{k}" }
      expect(result).to eq('block_TOTALLY_MISSING_XYZ')
    end

    it 'reads docker secrets via _FILE convention' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'secret')
        File.write(path, 'secret_value')
        ENV['DB_PASS_FILE'] = path
        expect(described_class.fetch('DB_PASS')).to eq('secret_value')
      end
    end
  end

  describe '.[]' do
    it 'returns the value when key exists' do
      ENV['TEST_KEY'] = 'world'
      expect(described_class['TEST_KEY']).to eq('world')
    end

    it 'raises KeyError for missing key' do
      expect { described_class['TOTALLY_MISSING_XYZ'] }.to raise_error(KeyError)
    end
  end

  describe '.configure' do
    it 'sets cache_enabled' do
      described_class.configure { |c| c.cache_enabled = true }
      expect(described_class.configuration.cache_enabled?).to be true
    end

    it 'sets cache_ttl' do
      described_class.configure { |c| c.cache_ttl = 300 }
      expect(described_class.configuration.cache_ttl).to eq(300)
    end

    it 'sets cache_max_size' do
      described_class.configure { |c| c.cache_max_size = 64 }
      expect(described_class.configuration.cache_max_size).to eq(64)
    end

    # Fix #1: fetcher must be rebuilt so new cache/TTL settings take effect.
    it 'rebuilds the fetcher so subsequent fetches use the new cache' do
      ENV['REBUILD_KEY'] = 'value'
      described_class.fetch('REBUILD_KEY') # initialises @fetcher
      fetcher_before = described_class.send(:fetcher)

      described_class.configure { |c| c.cache_ttl = 300 }

      expect(described_class.send(:fetcher)).not_to equal(fetcher_before)
    end

    # Fix #5: configure holds the mutex for its entire block, so a concurrent
    # fetch cannot observe a half-updated configuration.
    it 'is safe to call concurrently with fetch' do
      ENV['CONCURRENT_KEY'] = 'value'
      exceptions = []

      threads = Array.new(4) { Thread.new { described_class.configure { |c| c.cache_enabled = false } } } +
                Array.new(4) do
                  Thread.new do
                    described_class.fetch('CONCURRENT_KEY')
                  rescue StandardError
                    nil
                  end
                end

      threads.each { |t| t.join(5) }
      expect(exceptions).to be_empty
    end
  end

  describe '.reset!' do
    it 'clears configuration back to defaults' do
      described_class.configure { |c| c.cache_enabled = true }
      described_class.reset!
      expect(described_class.configuration.cache_enabled?).to be false
    end
  end

  describe '.build_mutex (#4)' do
    context 'when Async::Mutex is defined' do
      before { stub_const('Async::Mutex', Class.new(Mutex)) }

      it 'returns an Async::Mutex instance' do
        expect(described_class.send(:build_mutex)).to be_a(Async::Mutex)
      end
    end

    context 'when Async::Mutex is not defined' do
      it 'returns a ::Mutex instance' do
        expect(described_class.send(:build_mutex)).to be_a(Mutex)
      end
    end
  end

  describe 'fetcher memoisation (#2)' do
    it 'returns the same fetcher instance on repeated calls' do
      ENV['MEMO_KEY'] = 'value'
      described_class.fetch('MEMO_KEY')
      expect(described_class.send(:fetcher)).to equal(described_class.send(:fetcher))
    end
  end
end
