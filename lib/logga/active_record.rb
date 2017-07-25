module Logga
  module ActiveRecord
    extend ActiveSupport::Concern

    EXCLUDED_KEYS          = [:created_at, :updated_at, :log, :sent_photos_chaser_email, :sent_after_sales_emails]
    EXCLUDED_KEYS_SUFFIXES = [:_id, :_filenames]

    included do
      class_attribute :log_fields, instance_writer: false
      self.log_fields = {}
    end

    class_methods do
      def add_log_entries_for(*actions, to: :self, fields: {})
        after_create :log_model_creation if actions.include?(:create)
        after_update :log_model_changes  if actions.include?(:update)
        define_method(:log_receiver) { to == :self ? self : send(to) }
        self.log_fields = fields
      end
    end

    def log_model_creation
      body_generator = ->(record) { default_creation_log_body(record) }
      body = log_fields.fetch(:created_at, body_generator).call(self)
      log_receiver.log_entries.create(author_data.merge(body: body))
    end

    def log_model_changes
      field_changes = changes.reject do |k, _|
        EXCLUDED_KEYS.include?(k.to_sym) ||
        EXCLUDED_KEYS_SUFFIXES.any? { |suffix| k.to_s.end_with?(suffix.to_s) }
      end
      log_field_changes(field_changes)
    end

    def log_field_changes(changes)
      body_generator = ->(record, field, old_value, new_value) { default_change_log_body(record, field, old_value, new_value) }
      body = changes.inject([]) do |body, (field, (old_value, new_value))|
        body << log_fields.fetch(field.to_sym, body_generator).call(self, field, old_value, new_value)
      end.join('\n')
      log_receiver.log_entries.create(author_data.merge(body: body))
    end

    def author_data
      data = Hash(log_receiver.author).with_indifferent_access
      {
          author_id:   data[:id],
          author_type: data[:type],
          author_name: data[:name]
      }
    end

    def default_creation_log_body(record)
      [
        "#{record.class.name.demodulize} created",
        ("(#{record.state})" if record.try(:state))
      ].compact.join(' ')
    end

    def default_change_log_body(record, field, old_value, new_value)
      "#{record.class.name.demodulize} #{field} set to #{new_value}"
    end
  end
end
