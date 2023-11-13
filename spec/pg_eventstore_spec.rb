# frozen_string_literal: true

RSpec.describe PgEventstore do
  it "has a version number" do
    expect(PgEventstore::VERSION).not_to be nil
  end
end
