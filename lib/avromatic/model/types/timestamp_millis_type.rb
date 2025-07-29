# frozen_string_literal: true

require 'avromatic/model/types/abstract_timestamp_type'

module Avromatic
  module Model
    module Types

      # This subclass is used to truncate timestamp values to milliseconds.
      class TimestampMillisType < Avromatic::Model::Types::AbstractTimestampType

        def name
          'timestamp-millis'
        end

        def referenced_model_classes
          EMPTY_ARRAY
        end

        private

        def truncated?(value)
          value.nsec % 1_000_000 == 0
        end

        def coerce_time(input)
          # .iso8601 raises an error if the input is not a valid ISO 8601 string
          # it is handled by the caller
          return Time.iso8601(input) if input.is_a?(String)

          # value is coerced to a local Time
          # The Avro representation of a timestamp is Epoch seconds, independent
          # of time zone.
          ::Time.at(input.to_i, input.usec / 1000 * 1000)
        end
      end
    end
  end
end
