require 'spec_helper'
require 'avro/builder'

describe Avromatic::Model::RawSerialization do
  let(:values) { { id: rand(99) } }
  let(:test_class) { Avromatic::Model.model(value_schema_name: schema_name) }
  let(:instance) { test_class.new(values) }
  let(:avro_raw_value) { instance.avro_raw_value }
  let(:avro_raw_key) { instance.avro_raw_key }
  let(:use_custom_datum_writer) { true }
  let(:member_index) { Avromatic::IO::UNION_MEMBER_INDEX }
  let(:encoding_provider) { Avromatic::IO::ENCODING_PROVIDER }

  before do
    # Ensure that there is no dependency on messaging
    Avromatic.messaging = nil
    allow(Avromatic).to receive(:use_custom_datum_writer).and_return(use_custom_datum_writer)
  end

  describe "#value_attributes_for_avro" do
    let(:schema_name) { 'test.encode_value' }
    let(:values) { { str1: 'a', str2: 'b' } }

    it "returns a hash of attributes that will be encoded using avro" do
      expected = values.stringify_keys
      expect(instance.value_attributes_for_avro).to eq(expected)
    end

    context "with a nested record" do
      let(:schema_name) { 'test.nested_record' }
      let(:sub) { test_class.nested_models['test.__nested_record_sub_record'].new(str: 'b', i: 1) }
      let(:values) { { str: 'a', sub: sub } }

      it "reuses cacheable attributes" do
        expected = values.deep_stringify_keys
        expected['sub'] = { encoding_provider => sub }
        actual = instance.value_attributes_for_avro
        expect(actual).to eq(expected)
        expect(actual['sub'][encoding_provider]).to equal(sub)
      end
    end

    context "with repeated references to a named type" do
      let(:schema_name) { 'test.wrapper' }
      let(:wrapped1) { test_class.nested_models['test.wrapped1'].new(i: 42) }
      let(:wrapped2) { test_class.nested_models['test.wrapped2'].new(i: 78) }
      let(:values) { { sub1: wrapped1, sub2: wrapped1, sub3: wrapped2 } }

      it "reuses cacheable attributes" do
        expected = values.deep_stringify_keys.each_with_object({}) { |(k, v), hash| hash[k] = { encoding_provider => v } }
        actual = instance.value_attributes_for_avro
        expect(actual).to eq(expected)
        expect(actual['sub1'][encoding_provider]).to equal(wrapped1)
        expect(actual['sub2'][encoding_provider]).to equal(wrapped1)
        expect(actual['sub3'][encoding_provider]).to equal(wrapped2)
      end
    end

    context "with reference to a mutable attribute" do
      let(:schema_name) { 'test.wrapper' }
      let(:wrapped1_class) { test_class.nested_models['test.wrapped1'] }
      let(:wrapped2_class) { test_class.nested_models['test.wrapped2'] }
      let(:wrapped1) { wrapped1_class.new(i: 42) }
      let(:wrapped2) { wrapped1_class.new(i: 78) }
      let(:wrapped3) { wrapped2_class.new(i: 96) }
      let(:values) { { sub1: wrapped1, sub2: wrapped2, sub3: wrapped3 } }

      before do
        allow(wrapped1_class.config).to receive(:mutable).and_return(true)
      end

      it "doesn't cache mutable attributes" do
        expected = values.deep_stringify_keys
        expected['sub1'] = wrapped1.value_attributes_for_avro
        expected['sub2'] = wrapped2.value_attributes_for_avro
        expected['sub3'] = { encoding_provider => wrapped3 }
        actual = instance.value_attributes_for_avro
        expect(actual).to eq(expected)
        expect(actual['sub1'][encoding_provider]).not_to equal(wrapped1)
        expect(actual['sub2'][encoding_provider]).not_to equal(wrapped2)
        expect(actual['sub3'][encoding_provider]).to equal(wrapped3)
      end
    end

    context "caching" do
      context "immutable model" do
        it "caches a hash of attributes that will be encoded using avro" do
          value_attributes1 = instance.value_attributes_for_avro
          value_attributes2 = instance.value_attributes_for_avro
          expect(value_attributes1).to equal(value_attributes2)
        end

        it "caches the avro encoding" do
          encoded1 = instance.avro_raw_value
          encoded2 = instance.avro_raw_value
          expect(encoded1).to equal(encoded2)
        end
      end

      context "mutable model" do
        let(:test_class) do
          Avromatic::Model.model(value_schema_name: 'test.encode_value', mutable: true)
        end

        it "doesn't cache hash of attributes that will be encoded using avro" do
          value_attributes1 = instance.value_attributes_for_avro
          value_attributes2 = instance.value_attributes_for_avro
          expect(value_attributes1).not_to equal(value_attributes2)
        end

        it "doesn't cache the avro encoding" do
          encoded1 = instance.avro_raw_value
          encoded2 = instance.avro_raw_value
          expect(encoded1).not_to equal(encoded2)
        end
      end
    end

    context "a record with a union" do
      let(:schema_name) { 'test.real_union' }
      let(:bar_message) { test_class.nested_models['test.bar'].new(bar_message: "I'm a bar") }
      let(:values) do
        {
          header: 'has bar',
          message: bar_message
        }
      end

      it "includes union member index in the hash of attributes" do
        expected = values.deep_stringify_keys
        expected['message'] = { encoding_provider => bar_message, member_index => 1 }
        actual = instance.value_attributes_for_avro
        expect(actual).to eq(expected)
        expect(actual['message'][encoding_provider]).to equal(bar_message)
      end

      context "when use_custom_datum_writer is false" do
        let(:use_custom_datum_writer) { false }
        let(:bar_message) { { bar_message: "I'm a bar" } }

        it "does not include union member index in the hash of attributes" do
          expected = values.deep_stringify_keys
          expect(instance.value_attributes_for_avro).to eq(expected)
        end
      end
    end
  end

  describe "#key_attributes_for_avro" do
    let(:test_class) do
      Avromatic::Model.model(
        value_schema_name: 'test.encode_value',
        key_schema_name: 'test.encode_key'
      )
    end
    let(:values) { super().merge!(str1: 'a', str2: 'b') }

    it "returns a hash of the key attributes that will be encoded using avro" do
      expected = { 'id' => values[:id] }
      expect(instance.key_attributes_for_avro).to eq(expected)
    end
  end

  describe "#avro_raw_value" do
    let(:schema_name) { 'test.encode_value' }
    let(:values) { { str1: 'a', str2: 'b' } }

    it "encodes the value for the model" do
      encoded_value = instance.avro_raw_value
      decoded = test_class.avro_raw_decode(value: encoded_value)
      expect(decoded).to eq(instance)
    end

    context "with a nested record" do
      let(:schema_name) { 'test.nested_record' }
      let(:values) { { str: 'a', sub: { str: 'b', i: 1 } } }

      it "encodes the value for the model" do
        encoded_value = instance.avro_raw_value
        decoded = test_class.avro_raw_decode(value: encoded_value)
        expect(decoded).to eq(instance)
      end
    end
  end

  describe "#avro_raw_key" do
    let(:test_class) do
      Avromatic::Model.model(
        value_schema_name: 'test.encode_value',
        key_schema_name: 'test.encode_key'
      )
    end
    let(:values) { super().merge!(str1: 'a', str2: 'b') }

    it "encodes the key for the model" do
      encoded_value = instance.avro_raw_value
      encoded_key = instance.avro_raw_key
      decoded = test_class.avro_raw_decode(key: encoded_key, value: encoded_value)
      expect(decoded).to eq(instance)
    end

    context "when a model does not have a key schema" do
      let(:test_class) do
        Avromatic::Model.model(value_schema_name: 'test.encode_value')
      end
      let(:values) { { str1: 'a', str2: 'b' } }

      it "raises an error" do
        expect { instance.avro_raw_key }.to raise_error('Model has no key schema')
      end
    end
  end

  describe ".raw_decode" do
    let(:schema_name) { 'test.encode_value' }
    let(:values) { { str1: 'a', str2: 'b' } }

    it "decodes a model" do
      decoded = test_class.avro_raw_decode(value: avro_raw_value)
      expect(decoded).to eq(instance)
    end

    context "when a value and a key are specified" do
      let(:test_class) do
        Avromatic::Model.model(
          value_schema_name: 'test.encode_value',
          key_schema_name: 'test.encode_key'
        )
      end
      let(:values) { { id: rand(99), str1: 'a', str2: 'b' } }

      it "decodes a model" do
        decoded = test_class.avro_raw_decode(key: avro_raw_key, value: avro_raw_value)
        expect(decoded).to eq(instance)
      end

      context "when the writers schemas are different" do
        # schema names for reader and writer must match
        let(:writer_value_schema) do
          Avro::Builder.build_schema do
            record :encode_value, namespace: :test do
              required :str1, :string, default: 'X'
              required :str3, :string, default: 'Z'
            end
          end
        end
        let(:writer_key_schema) do
          Avro::Builder.build_schema do
            record :encode_key, namespace: :test do
              required :id, :int
              required :id_type, :string, default: 'regular'
            end
          end
        end
        let(:writer_test_class) do
          Avromatic::Model.model(value_schema: writer_value_schema,
                                 key_schema: writer_key_schema)
        end
        let(:instance) { writer_test_class.new(values) }
        let(:values) do
          { id: rand(99), id_type: 'admin', str1: 'a', str3: 'c' }
        end

        it "decodes a model based on the writers schema and the model schemas" do
          decoded = test_class.avro_raw_decode(key: avro_raw_key,
                                               value: avro_raw_value,
                                               key_schema: writer_key_schema,
                                               value_schema: writer_value_schema)

          expect(decoded.attributes).to eq(id: values[:id], str1: 'a', str2: 'Y')
        end
      end
    end
  end

  it_behaves_like "logical type encoding and decoding" do
    let(:decoded) { test_class.avro_raw_decode(value: avro_raw_value) }
  end

  context "nested serialization" do
    context "array of array of records" do
      let(:schema) do
        Avro::Builder.build_schema do
          record :int_rec do
            required :i, :int
          end

          record :transform do
            required :matrix, :array, items: array(:int_rec)
          end
        end
      end
      let(:test_class) do
        Avromatic::Model.model(schema: schema)
      end
      let(:values) do
        { matrix: [[{ i: 1 }, { i: 2 }], [{ i: 3 }, { i: 4 }]] }
      end
      let(:decoded) { test_class.avro_raw_decode(value: avro_raw_value) }

      it "encodes and decodes the model" do
        expect(instance).to eq(decoded)
      end
    end

    context "array of pre-registered nested models" do
      let(:nested_schema) do
        Avro::Builder.build_schema do
          record :int_rec do
            required :i, :int
          end
        end
      end
      let!(:nested_model) do
        Avromatic::Model.model(schema: nested_schema)
      end
      let(:schema) do
        Avro::Builder.build_schema do
          record :int_rec do
            required :i, :int
          end

          record :transform do
            required :a, :array, items: :int_rec
          end
        end
      end
      let(:test_class) do
        Avromatic::Model.model(schema: schema)
      end
      let(:values) do
        { a: [{ i: 1 }, { i: 2 }] }
      end
      let(:decoded) { test_class.avro_raw_decode(value: avro_raw_value) }

      it "encodes and decodes the model" do
        expect(instance).to eq(decoded)
      end
    end

    context "array of unions" do
      let(:schema) do
        Avro::Builder.build_schema do
          record :str_rec do
            required :s, :string
          end

          record :int_rec do
            required :i, :int
          end

          record :mgmt do
            required :unions, :array, items: union(:str_rec, :int_rec)
          end
        end
      end
      let(:test_class) do
        Avromatic::Model.model(schema: schema)
      end
      let(:values) do
        { unions: [{ s: 'A' }, { i: 1 }, { s: 'C' }] }
      end
      let(:decoded) { test_class.avro_raw_decode(value: avro_raw_value) }

      it "includes union member index" do
        expect(instance.value_attributes_for_avro['unions'].map { |v| v[member_index] }).to eq([0, 1, 0])
      end

      context "when use_custom_datum_writer is false" do
        let(:use_custom_datum_writer) { false }

        it "does not include union member index" do
          expect(instance.value_attributes_for_avro['unions'].map { |v| v[member_index] }).to eq([nil] * 3)
        end
      end

      it "encodes and decodes the model" do
        expect(instance).to eq(decoded)
      end
    end

    context "map of unions" do
      let(:schema) do
        Avro::Builder.build_schema do
          record :str_rec do
            required :s, :string
          end

          record :int_rec do
            required :i, :int
          end

          record :mgmt do
            required :union_map, :map, values: union(:str_rec, :int_rec)
          end
        end
      end
      let(:test_class) do
        Avromatic::Model.model(schema: schema)
      end
      let(:values) do
        { union_map: {
          'str' => { s: 'A' },
          'int' => { i: 22 }
        } }
      end
      let(:decoded) { test_class.avro_raw_decode(value: avro_raw_value) }

      it "includes union member index" do
        expect(instance.value_attributes_for_avro['union_map'].values.map { |v| v[member_index] }).to eq([0, 1])
      end

      context "when use_custom_datum_writer is false" do
        let(:use_custom_datum_writer) { false }

        it "does not include union member index" do
          expect(instance.value_attributes_for_avro['union_map'].values.map { |v| v[member_index] }).to eq([nil] * 2)
        end
      end

      it "encodes and decodes the model" do
        expect(instance).to eq(decoded)
      end
    end
  end

  context "custom types" do
    let(:schema_name) { 'test.named_type' }
    let(:test_class) do
      Avromatic::Model.model(schema_name: schema_name)
    end
    let(:values) { { six_str: 'fOObAR' } }
    let(:decoded) { test_class.send(:decode_avro_datum, avro_raw_value) }

    context "with a value class" do
      let(:value_class) do
        Class.new do
          attr_reader :value

          def initialize(value)
            @value = value
          end

          def self.from_avro(value)
            new(value.downcase)
          end

          def self.to_avro(value)
            value.value.capitalize
          end
        end
      end

      before do
        Avromatic.register_type('test.six', value_class)
      end

      it "converts when encoding the value" do
        expect(decoded['six_str']).to eq('Foobar')
      end
    end

    context "without a value class" do
      before do
        Avromatic.register_type('test.six') do |type|
          type.from_avro = ->(value) { value.downcase }
          type.to_avro = ->(value) { value.capitalize }
        end
      end

      it "converts when encoding the value" do
        expect(decoded['six_str']).to eq('Foobar')
      end
    end

    context "custom type in a union" do
      let(:values) { { optional_six: 'fOObAR' } }

      before do
        Avromatic.register_type('test.six') do |type|
          type.from_avro = ->(value) { value.downcase }
          type.to_avro = ->(value) { value.capitalize }
        end
      end

      it "converts when encoding the value" do
        expect(decoded['optional_six']).to eq('Foobar')
      end
    end

    context "custom type for record" do
      let(:schema_name) { 'test.with_varchar' }
      let(:test_class) do
        Avromatic::Model.model(schema_name: schema_name)
      end
      let(:values) { { str: 'test' } }

      before do
        Avromatic.register_type('test.varchar', String) do |type|
          type.from_avro = ->(value) do
            value.is_a?(String) ? value : value['data']
          end
          type.to_avro = ->(value) do
            { 'data' => value, 'length' => value.size }
          end
        end
      end

      it "converts when encoding the value" do
        expect(decoded['str']).to eq('length' => 4, 'data' => 'test')
      end
    end
  end

end
