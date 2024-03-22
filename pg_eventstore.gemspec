# frozen_string_literal: true

require_relative "lib/pg_eventstore/version"

Gem::Specification.new do |spec|
  spec.name = "pg_eventstore"
  spec.version = PgEventstore::VERSION
  spec.authors = ["Ivan Dzyzenko"]
  spec.email = ["ivan.dzyzenko@gmail.com"]

  spec.summary = "EventStore implementation using PostgreSQL"
  spec.description = "EventStore implementation using PostgreSQL"
  spec.homepage = "https://github.com/yousty/pg_eventstore"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/yousty/pg_eventstore"
  spec.metadata["changelog_uri"] = "https://github.com/yousty/pg_eventstore/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    paths_to_exclude = %w[
      bin/ test/ spec/ features/ .git .circleci appveyor Gemfile .ruby-version .ruby-gemset .rspec docker-compose.yml
      Rakefile benchmark/ .yardopts db/structure.sql config.ru
    ]
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*paths_to_exclude)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "pg", "~> 1.5"
  spec.add_dependency "connection_pool", "~> 2.4"
  spec.add_dependency "sinatra", "~> 4.0"
end
