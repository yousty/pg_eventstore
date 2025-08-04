# frozen_string_literal: true

# This matcher is defined to test options which are defined by using
# PgEventstore::Extensions::OptionsExtension option. Example:
# Let's say you have next class
# class SomeClass
#   include PgEventstore::Extensions::OptionsExtension
#
#   option(:some_opt, metadata: { foo: :bar }) { '1' }
# end
#
# To test that its instance has the proper option with the proper default value and proper metadata you can use this
# matcher:
# RSpec.describe SomeClass do
#   subject { described_class.new }
#
#   # Check that :some_opt is present
#   it { is_expected.to have_option(:some_opt) }
#   # Check that :some_opt is present and has the correct default value
#   it { is_expected.to have_option(:some_opt).with_default_value('1').with_metadata(foo: :bar) }
# end
RSpec::Matchers.define :has_option do |option_name|
  match do |obj|
    option = obj.class.options[option_name]
    is_correct = obj.class.respond_to?(:options) && option
    if defined?(@default_value)
      is_correct &&=
        RSpec::Matchers::BuiltIn::Match.new(@default_value).matches?(obj.class.allocate.public_send(option_name))
    end
    is_correct &&= RSpec::Matchers::BuiltIn::Match.new(@metadata).matches?(option.metadata) if defined?(@metadata)
    is_correct
  end

  failure_message do |obj|
    option = obj.class.options[option_name]
    option_presence = obj.class.respond_to?(:options) && option

    default_value_message = "with default value #{@default_value.inspect}"
    metadata_message = "with metadata #{@metadata.inspect}"
    message = "Expected #{obj.class} to have `#{option_name.inspect}' option"
    message += " #{default_value_message}," if defined?(@default_value)
    message += " #{metadata_message}," if defined?(@metadata)
    message += ',' unless defined?(@metadata) || defined?(@default_value)
    if option_presence
      actual_default_value = obj.class.allocate.public_send(option_name)
      actual_metadata = option.metadata
      default_value_matches = RSpec::Matchers::BuiltIn::Match.new(@default_value).matches?(actual_default_value)
      metadata_matches = RSpec::Matchers::BuiltIn::Match.new(@metadata).matches?(actual_metadata)

      message +=
        case [default_value_matches, metadata_matches]
        when [false, true]
          " but default value is #{actual_default_value.inspect}"
        when [true, false]
          " but metadata is #{actual_metadata.inspect}"
        else
          " but default value is #{actual_default_value.inspect} and metadata is #{actual_metadata.inspect}"
        end
    else
      message += ' but there is no option found with the given name'
    end
    message
  end

  description do
    expected_list = RSpec::Matchers::EnglishPhrasing.list(expected)
    sentences =
      @chained_method_clauses.map do |(method_name, method_args)|
        next '' if method_name == :required_kwargs

        english_name = RSpec::Matchers::EnglishPhrasing.split_words(method_name)
        arg_list = RSpec::Matchers::EnglishPhrasing.list(method_args)
        " #{english_name}#{arg_list}"
      end.join

    "have#{expected_list} option#{sentences}"
  end

  chain :with_default_value do |val|
    @default_value = val
  end

  chain :with_metadata do |val|
    @metadata = val
  end
end

RSpec::Matchers.alias_matcher :have_option, :has_option
RSpec::Matchers.alias_matcher :has_attribute, :has_option
RSpec::Matchers.alias_matcher :have_attribute, :has_option
