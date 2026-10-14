# frozen_string_literal: true

module ConformanceKit
  module Checks
    # "a boot-finalized configuration": after `finalize`, every reader returns a
    # Ractor-shareable value. Readers are `Method` objects (named
    # `Owner.reader`), a `{ "name" => callable }` Hash, or bare callables (named
    # by source location).
    module BootFinalized
      NAME = "a boot-finalized configuration"

      class << self
        def call(readers:, finalize: nil)
          raise ArgumentError, "readers: is empty, so #{NAME} would check nothing" if readers.nil? || readers.empty?

          unless Shareability.available?
            return Result.skip("#{NAME} needs Ractor.shareable?, which #{RUBY_ENGINE} #{RUBY_VERSION} lacks")
          end

          finalize&.call
          named = name_readers(readers)
          offenses = named.filter_map { |name, reader| offense(name, reader) }
          return Result.pass if offenses.empty?

          Result.fail("#{NAME}: #{offenses.size} of #{named.size} readers returned a value " \
                      "that is not Ractor-shareable:\n#{offenses.map { "  #{_1}" }.join("\n")}")
        end

        private

        def offense(name, reader)
          value = reader.call
          culprit = Shareability.culprit(value)
          return nil unless culprit

          where = culprit.path.empty? ? "it is" : "#{culprit.path} is"
          "#{name} returned #{value.class}: #{where} #{culprit.reason}"
        rescue StandardError => e
          "#{name} raised #{e.class}: #{e.message}"
        end

        def name_readers(readers)
          return readers.map { |name, reader| [name.to_s, reader] } if readers.is_a?(::Hash)

          Array(readers).map { |reader| [reader_name(reader), reader] }
        end

        def reader_name(reader)
          case reader
          when ::Method
            receiver = reader.receiver
            receiver.is_a?(::Module) ? "#{receiver.name}.#{reader.name}" : "#{receiver.class.name}##{reader.name}"
          when ::Proc
            file, line = reader.source_location
            "the reader at #{file}:#{line}"
          else reader.inspect
          end
        end
      end
    end
  end
end
