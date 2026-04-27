# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require_relative '../../../../lib/rubocop/cop/container_env/prefer_container_env'

RSpec.describe RuboCop::Cop::ContainerEnv::PreferContainerEnv, :config do
  describe 'ENV[] read access' do
    it 'flags and autocorrects ENV[key]' do
      expect_offense(<<~RUBY)
        ENV['KEY']
        ^^^^^^^^^^ Use `ContainerEnv` instead of direct `ENV` access.
      RUBY
      expect_correction(<<~RUBY)
        ContainerEnv['KEY']
      RUBY
    end

    it 'flags and autocorrects ::ENV[key]' do
      expect_offense(<<~RUBY)
        ::ENV['KEY']
        ^^^^^^^^^^^^ Use `ContainerEnv` instead of direct `ENV` access.
      RUBY
      expect_correction(<<~RUBY)
        ContainerEnv['KEY']
      RUBY
    end
  end

  describe 'ENV.fetch access' do
    it 'flags and autocorrects ENV.fetch with no default' do
      expect_offense(<<~RUBY)
        ENV.fetch('KEY')
        ^^^^^^^^^^^^^^^^ Use `ContainerEnv` instead of direct `ENV` access.
      RUBY
      expect_correction(<<~RUBY)
        ContainerEnv.fetch('KEY')
      RUBY
    end

    it 'flags and autocorrects ENV.fetch with a default value' do
      expect_offense(<<~RUBY)
        ENV.fetch('KEY', 'default')
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^ Use `ContainerEnv` instead of direct `ENV` access.
      RUBY
      expect_correction(<<~RUBY)
        ContainerEnv.fetch('KEY', 'default')
      RUBY
    end

    it 'flags the send node and autocorrects ENV.fetch with a block' do
      expect_offense(<<~RUBY)
        ENV.fetch('KEY') { |k| k }
        ^^^^^^^^^^^^^^^^ Use `ContainerEnv` instead of direct `ENV` access.
      RUBY
      expect_correction(<<~RUBY)
        ContainerEnv.fetch('KEY') { |k| k }
      RUBY
    end
  end

  describe 'methods that are not flagged' do
    it 'does not flag ENV[]= writes' do
      expect_no_offenses(<<~RUBY)
        ENV['KEY'] = 'value'
      RUBY
    end

    it 'does not flag ENV.to_h' do
      expect_no_offenses('ENV.to_h')
    end

    it 'does not flag ENV.each' do
      expect_no_offenses('ENV.each { |k, v| puts k }')
    end

    it 'does not flag ENV.replace (used in test setup)' do
      expect_no_offenses('ENV.replace(original)')
    end

    it 'does not flag ENV.delete' do
      expect_no_offenses("ENV.delete('KEY')")
    end
  end

  describe 'non-ENV constants' do
    it 'does not flag a hash variable named env' do
      expect_no_offenses("env['KEY']")
    end

    it 'does not flag a namespaced constant My::ENV' do
      expect_no_offenses("My::ENV['KEY']")
    end

    it 'does not flag other constants with bracket access' do
      expect_no_offenses("SETTINGS['KEY']")
    end
  end
end
