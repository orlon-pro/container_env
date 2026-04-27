# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe ContainerEnv::Fetcher do
  subject(:fetcher) { described_class.new(env: env, cache: cache, config: config) }

  let(:env) { {} }
  let(:config) { ContainerEnv::Configuration.new }
  let(:cache) { ContainerEnv::Cache.new(ttl: 600) }

  describe '#fetch' do
    context 'when key exists in env' do
      let(:env) { { 'DATABASE_URL' => 'postgres://localhost/db' } }

      it 'returns the value' do
        expect(fetcher.fetch('DATABASE_URL')).to eq('postgres://localhost/db')
      end
    end

    context 'when key is missing' do
      it 'raises KeyError with no default' do
        expect { fetcher.fetch('MISSING') }.to raise_error(KeyError, /MISSING/)
      end

      it 'returns the default value when provided' do
        expect(fetcher.fetch('MISSING', 'default')).to eq('default')
      end

      it 'returns nil when nil is given as default' do
        expect(fetcher.fetch('MISSING', nil)).to be_nil
      end

      it 'calls the block and returns its value' do
        result = fetcher.fetch('MISSING') { |k| "block_#{k}" }
        expect(result).to eq('block_MISSING')
      end

      it 'passes the key to the block' do
        received_key = nil
        fetcher.fetch('MISSING') { |k| received_key = k }
        expect(received_key).to eq('MISSING')
      end
    end

    context 'when _FILE env var exists' do
      it 'reads the value from the file' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'secret')
          File.write(path, "s3cr3t\n")
          env['DATABASE_URL_FILE'] = path

          expect(fetcher.fetch('DATABASE_URL')).to eq('s3cr3t')
        end
      end

      it 'chomps trailing newlines from the file' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'secret')
          File.write(path, "value\n\n")
          env['KEY_FILE'] = path

          expect(fetcher.fetch('KEY')).to eq("value\n")
        end
      end

      it 'raises KeyError if the file path is not readable' do
        env['KEY_FILE'] = '/nonexistent/path/secret'
        expect { fetcher.fetch('KEY') }.to raise_error(KeyError)
      end

      it 'prefers direct ENV over _FILE' do
        Dir.mktmpdir do |dir|
          path = File.join(dir, 'secret')
          File.write(path, 'from_file')
          env['KEY'] = 'from_env'
          env['KEY_FILE'] = path

          expect(fetcher.fetch('KEY')).to eq('from_env')
        end
      end
    end

    context 'with caching enabled' do
      before { config.cache_enabled = true }

      it 'caches the result on first lookup' do
        env['KEY'] = 'original'
        fetcher.fetch('KEY')
        env.delete('KEY')

        expect(fetcher.fetch('KEY')).to eq('original')
      end

      it 'returns the cached value even when ENV changes' do
        env['KEY'] = 'original'
        fetcher.fetch('KEY')
        env['KEY'] = 'changed'

        expect(fetcher.fetch('KEY')).to eq('original')
      end
    end

    context 'with caching disabled' do
      it 'reflects ENV changes immediately' do
        env['KEY'] = 'original'
        fetcher.fetch('KEY')
        env['KEY'] = 'changed'

        expect(fetcher.fetch('KEY')).to eq('changed')
      end

      it 'does not use the cache' do
        allow(cache).to receive(:fetch_or_store).and_call_original
        env['KEY'] = 'value'
        fetcher.fetch('KEY')

        expect(cache).not_to have_received(:fetch_or_store)
      end
    end
  end

  describe '#[]' do
    context 'when key exists' do
      let(:env) { { 'FOO' => 'bar' } }

      it 'returns the value' do
        expect(fetcher['FOO']).to eq('bar')
      end
    end

    context 'when key is missing' do
      it 'raises KeyError' do
        expect { fetcher['MISSING'] }.to raise_error(KeyError)
      end
    end
  end
end
