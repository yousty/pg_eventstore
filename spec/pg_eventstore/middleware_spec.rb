# frozen_string_literal: true

RSpec.describe PgEventstore::Middleware do
  let(:middleware_class) do
    Class.new do
      include PgEventstore::Middleware
    end
  end

  describe '#deserialize_on_append?' do
    subject { middleware_class.new.deserialize_on_append? }

    it { is_expected.to eq(true) }

    context 'when a middleware overrides it' do
      let(:middleware_class) do
        Class.new do
          include PgEventstore::Middleware

          def deserialize_on_append?
            false
          end
        end
      end

      it { is_expected.to eq(false) }
    end
  end
end
