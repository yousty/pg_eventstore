# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "pg_eventstore"

load "pg_eventstore/tasks/setup.rake"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
