# frozen_string_literal: true

require "stringio"

module ConformanceKit
  module Ractorize
    # One request the ractorize job serves. Its env is built on the main Ractor
    # from Strings only, so it crosses into the request Ractor as a copy; the
    # IO objects Rack wants are made inside that Ractor.
    module Request
      SERVER = {
        "SCRIPT_NAME" => "",
        "SERVER_NAME" => "localhost",
        "SERVER_PORT" => "80",
        "SERVER_PROTOCOL" => "HTTP/1.1",
        "HTTP_HOST" => "localhost",
        "HTTP_ACCEPT" => "text/html",
        "rack.url_scheme" => "http"
      }.freeze

      def self.env_for(path)
        path_info, query = path.split("?", 2)
        { "REQUEST_METHOD" => "GET", "PATH_INFO" => path_info, "QUERY_STRING" => query.to_s }.merge(SERVER)
      end

      # `{ status:, body:, error: }`, where error is describe_error's triple:
      # the exception the app raised, or the one its error page swallowed.
      def self.serve(app, path)
        Ractor.new(app, env_for(path)) { |rack_app, env| Request.call(rack_app, env) }.value
      end

      # Runs inside the request Ractor.
      def self.call(app, env)
        env = env.merge("rack.input" => StringIO.new(+""), "rack.errors" => StringIO.new)
        status, _headers, body = app.call(env)
        text = read(body)
        swallowed = env["action_dispatch.exception"]
        { status: status, body: text, error: swallowed && describe_error(swallowed) }
      rescue Exception => e # rubocop:disable Lint/RescueException -- every failure is the report
        { status: nil, body: nil, error: describe_error(e) }
      end

      def self.read(body)
        text = +""
        body.each { text << _1 }
        text
      ensure
        body.close if body.respond_to?(:close)
      end

      # The root cause's class, message and first frame, unfiltered (no
      # backtrace cleaner), so the frame names the file and line to fix.
      def self.describe_error(error)
        root = error
        root = root.cause while root.cause
        [root.class.name, root.message, root.backtrace&.first]
      end
    end
  end
end
