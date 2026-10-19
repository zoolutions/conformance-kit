# frozen_string_literal: true

require "conformance_kit/ractorize/request"

RSpec.describe ConformanceKit::Ractorize::Request do
  describe ".env_for" do
    it "builds a GET env on the main Ractor, without IO objects, so it can be passed to a Ractor" do
      env = described_class.env_for("/widgets?page=2")

      expect(env).to include("REQUEST_METHOD" => "GET", "PATH_INFO" => "/widgets", "QUERY_STRING" => "page=2",
                             "SERVER_NAME" => "localhost", "rack.url_scheme" => "http")
      expect(env.keys).not_to include("rack.input", "rack.errors")
      expect(env.values).to all(be_a(String))
    end
  end

  describe ".describe_error" do
    it "names the root cause, its message and its first frame, unfiltered" do
      error = begin
        begin
          raise ArgumentError, "the root"
        rescue ArgumentError
          raise "the wrapper"
        end
      rescue RuntimeError => e
        e
      end

      described = described_class.describe_error(error)

      expect(described).to eq(["ArgumentError", "the root", error.cause.backtrace.first])
      expect(described.last).to include("request_spec.rb")
    end
  end

  describe ".serve", :ractor do
    before do
      skip "needs Ruby 4.0 (Ractor#value)" unless defined?(Ractor) && Ractor.method_defined?(:value)
    end

    def app(&) = Ractor.shareable_proc(&)

    it "serves the request inside a non-main Ractor and returns the status and body" do
      result = described_class.serve(app { |env| [200, {}, ["on #{env['PATH_INFO']}, main: #{Ractor.main?}"]] }, "/w")

      expect(result).to eq(status: 200, body: "on /w, main: false", error: nil)
    end

    it "returns the root cause when the app raises" do
      result = described_class.serve(app { |_env| raise KeyError, "missing" }, "/")

      expect(result[:status]).to be_nil
      expect(result[:error].first(2)).to eq(%w[KeyError missing])
    end

    it "returns the exception an error page swallowed (action_dispatch.exception)" do
      swallowing = app do |env|
        env["action_dispatch.exception"] = IndexError.new("swallowed")
        [500, {}, ["error page"]]
      end

      expect(described_class.serve(swallowing, "/"))
        .to include(status: 500, error: ["IndexError", "swallowed", nil])
    end
  end
end
