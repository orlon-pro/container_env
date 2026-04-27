# frozen_string_literal: true

module RuboCop
  module Cop
    module ContainerEnv
      # Flags direct `ENV` reads and suggests `ContainerEnv` instead.
      #
      # `ContainerEnv` transparently adds Docker secrets support and optional
      # caching on top of `ENV`. Accessing `ENV` directly bypasses both features.
      #
      # Write access (`ENV[]=`) and enumeration methods (`to_h`, `each`,
      # `replace`, etc.) are intentionally not flagged — they have no
      # `ContainerEnv` equivalent and are commonly used in test setup.
      #
      # @example
      #   # bad
      #   ENV['DATABASE_URL']
      #   ENV.fetch('DATABASE_URL')
      #   ENV.fetch('DATABASE_URL', 'postgres://localhost/dev')
      #   ENV.fetch('DATABASE_URL') { |k| "default for #{k}" }
      #
      #   # good
      #   ContainerEnv['DATABASE_URL']
      #   ContainerEnv.fetch('DATABASE_URL')
      #   ContainerEnv.fetch('DATABASE_URL', 'postgres://localhost/dev')
      #   ContainerEnv.fetch('DATABASE_URL') { |k| "default for #{k}" }
      #
      class PreferContainerEnv < RuboCop::Cop::Base
        extend RuboCop::Cop::AutoCorrector

        MSG = 'Use `ContainerEnv` instead of direct `ENV` access.'

        # Restricts which send nodes are delivered to on_send.
        # Only read/check methods that ContainerEnv implements are listed.
        RESTRICT_ON_SEND = %i[[] fetch].freeze

        # Matches bare ENV or top-level ::ENV, but not My::ENV.
        def_node_matcher :env_const?, '(const {nil? cbase} :ENV)'

        def on_send(node)
          return unless env_const?(node.receiver)

          add_offense(node) do |corrector|
            corrector.replace(node.receiver, 'ContainerEnv')
          end
        end
      end
    end
  end
end
