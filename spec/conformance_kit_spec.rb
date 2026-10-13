# frozen_string_literal: true

RSpec.describe ConformanceKit do
  it "has a version" do
    expect(ConformanceKit::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
