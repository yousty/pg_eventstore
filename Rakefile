# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'rake/extensiontask'

Rake::ExtensionTask.new('pg_eventstore_ext')

if ARGV.any? { |task_name| task_name.match?(/\Apg_eventstore:/) }
  require 'pg_eventstore'
  load 'pg_eventstore/tasks/setup.rake'
end

RSpec::Core::RakeTask.new(:spec)
task spec: :compile

task default: :spec
