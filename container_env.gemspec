# frozen_string_literal: true

require_relative 'lib/container_env/version'

Gem::Specification.new do |spec|
  spec.name = 'container_env'
  spec.version = ContainerEnv::VERSION
  spec.authors = ['orlon-pro']
  spec.summary = 'ENV wrapper with Docker secrets support, caching, and thread safety'
  spec.required_ruby_version = '>= 3.3.0'
  spec.license = 'MIT'

  spec.homepage = 'https://github.com/orlon-pro/container_env'

  spec.files = Dir['lib/**/*', 'LICENSE']
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
end
