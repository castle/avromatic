# frozen_string_literal: true

require 'avromatic/version'
require 'avro_schema_registry-client'
require 'ice_nine'
require 'ice_nine/core_ext/object'
require 'avromatic/model'
require 'avromatic/model_registry'
require 'avromatic/messaging'
require 'active_support/core_ext/string/inflections'

module Avromatic
  class << self
    attr_accessor :schema_registry, :registry_url, :schema_store, :logger,
                  :messaging, :custom_type_registry, :nested_models,
                  :use_custom_datum_reader, :use_custom_datum_writer,
                  :use_schema_fingerprint_lookup, :allow_unknown_attributes

    delegate :register_type, to: :custom_type_registry
  end

  self.nested_models = ModelRegistry.new
  self.logger = Logger.new($stdout)
  self.custom_type_registry = Avromatic::Model::CustomTypeRegistry.new
  self.use_custom_datum_reader = true
  self.use_custom_datum_writer = true
  self.use_schema_fingerprint_lookup = true
  self.allow_unknown_attributes = false

  def self.configure
    yield self
  end

  def self.build_schema_registry
    raise 'Avromatic must be configured with a registry_url' unless registry_url

    if use_schema_fingerprint_lookup
      AvroSchemaRegistry::CachedClient.new(
        AvroSchemaRegistry::Client.new(registry_url, logger: logger)
      )
    else
      AvroTurf::CachedConfluentSchemaRegistry.new(
        AvroTurf::ConfluentSchemaRegistry.new(registry_url, logger: logger)
      )
    end
  end

  def self.build_schema_registry!
    self.schema_registry = build_schema_registry
  end

  def self.build_messaging
    raise 'Avromatic must be configured with a schema_store' unless schema_store

    Avromatic::Messaging.new(
      registry: schema_registry || build_schema_registry,
      schema_store: schema_store,
      logger: logger
    )
  end

  def self.build_messaging!
    self.messaging = build_messaging
  end

  # This method is called as a Rails to_prepare hook after the application
  # first initializes during boot-up and prior to each code reloading.
  def self.prepare!
    nested_models.clear
    if schema_store
      if schema_store.respond_to?(:clear_schemas)
        schema_store.clear_schemas
      elsif schema_store.respond_to?(:clear)
        schema_store.clear
      end
    end

    eager_load_models!
  end

  def self.eager_load_models=(models)
    @eager_load_model_names = Array(models).map { |model| model.is_a?(Class) ? model.name : model }.freeze
  end

  def self.eager_load_models
    @eager_load_model_names
  end

  def self.eager_load_models!
    @eager_load_model_names&.each { |model_name| model_name.constantize.register! }
  end
  private_class_method :eager_load_models!

  def self.allow_decimal_logical_type
    ::Gem::Requirement.new('>= 1.11.0').satisfied_by?(::Gem::Version.new(::Avro::VERSION))
  end
end

require 'avromatic/railtie' if defined?(Rails)
