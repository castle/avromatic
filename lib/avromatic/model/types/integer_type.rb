# frozen_string_literal: true

require 'avromatic/model/types/abstract_type'

module Avromatic
  module Model
    module Types
      class IntegerType < AbstractType
        VALUE_CLASSES = [::Integer].freeze

        MAX_RANGE = 2**31

        def value_classes
          VALUE_CLASSES
        end

        def name
          'integer'
        end

        def coerce(input)
          if coercible?(input)
            input
          else
            raise ArgumentError.new("Could not coerce '#{input.inspect}' to #{name}")
          end
        end

        def matched?(value)
          value.is_a?(::Integer) && value.between?(-MAX_RANGE, MAX_RANGE - 1)
        end

        alias_method :coercible?, :coerced?

        def serialize(value, _strict)
          value
        end

        def referenced_model_classes
          EMPTY_ARRAY
        end
      end
    end
  end
end
