# frozen_string_literal: true

require 'active_record_compose/composed_collection'
require 'active_record_compose/delegate_attribute'
require 'active_record_compose/transaction_support'

module ActiveRecordCompose
  using ComposedCollection::PackagePrivate

  class Model
    include ActiveModel::Model
    include ActiveModel::Validations::Callbacks
    include ActiveModel::Attributes

    include ActiveRecordCompose::DelegateAttribute
    include ActiveRecordCompose::TransactionSupport

    # This flag controls the callback sequence for models.
    # The current default value is `true`, behavior when set to `false` will be removed in the next release.
    #
    # When `persisted_flag_callback_control` is set to `true`,
    # the occurrence of callbacks depends on the evaluation result of `#persisted?`.
    # Additionally, the definition of `#persisted?` itself can be appropriately overridden in subclasses.
    #
    # if `#persisted?` returns `false`:
    # * before_save
    # * before_create
    # * after_create
    # * after_save
    #
    # if `#persisted?` returns `true`:
    # * before_save
    # * before_update
    # * after_update
    # * after_save
    #
    # On the other hand, when `persisted_flag_callback_control` is set to `false`,
    # the invoked methods during saving operations vary depending on the method used.
    #
    # when performing `#save` or `#save!`:
    # * before_save
    # * after_save
    #
    # when performing `#update` or `#update!`:
    # * before_save
    # * before_update
    # * after_update
    # * after_save
    #
    # when performing `#create` or `#create!`:
    # * before_save
    # * before_create
    # * after_create
    # * after_save
    #
    class_attribute :persisted_flag_callback_control, instance_accessor: false, default: true

    define_model_callbacks :save
    define_model_callbacks :create
    define_model_callbacks :update

    validate :validate_models

    def initialize(attributes = {})
      super
    end

    # Save the models that exist in models.
    # Returns false if any of the targets fail, true if all succeed.
    #
    # The save is performed within a single transaction.
    #
    # Options like `:validate` and `:context` are not accepted as arguments.
    # The need for such values indicates that operations from multiple contexts are being handled.
    # However, if the contexts are different, it is recommended to separate them into different model definitions.
    #
    # @return [Boolean] returns true on success, false on failure.
    def save
      return false if invalid?

      with_transaction_returning_status do
        if self.class.persisted_flag_callback_control
          with_callbacks { save_models(bang: false) }
        else
          # steep:ignore:start
          deprecator.warn(
            'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
            'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
            '(Alternatively, exclude statements that set `false`)',
          )
          # steep:ignore:end
          run_callbacks(:save) { save_models(bang: false) }
        end
      rescue ActiveRecord::RecordInvalid
        false
      end
    end

    # Save the models that exist in models.
    # Unlike #save, an exception is raises on failure.
    #
    # Saving, like `#save`, is performed within a single transaction.
    #
    # Options like `:validate` and `:context` are not accepted as arguments.
    # The need for such values indicates that operations from multiple contexts are being handled.
    # However, if the contexts are different, it is recommended to separate them into different model definitions.
    #
    def save!
      valid? || raise_validation_error

      with_transaction_returning_status do
        if self.class.persisted_flag_callback_control
          with_callbacks { save_models(bang: true) }
        else
          # steep:ignore:start
          deprecator.warn(
            'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
            'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
            '(Alternatively, exclude statements that set `false`)',
          )
          # steep:ignore:end
          run_callbacks(:save) { save_models(bang: true) }
        end
      end || raise_on_save_error
    end

    # Behavior is same to `#save`, but `before_create` and `after_create` hooks fires.
    #
    #   class ComposedModel < ActiveRecordCompose::Model
    #     # ...
    #
    #     before_save { puts 'before_save called!' }
    #     before_create { puts 'before_create called!' }
    #     before_update { puts 'before_update called!' }
    #     after_save { puts 'after_save called!' }
    #     after_create { puts 'after_create called!' }
    #     after_update { puts 'after_update called!' }
    #   end
    #
    #   model = ComposedModel.new
    #
    #   model.save
    #   # before_save called!
    #   # after_save called!
    #
    #   model.create
    #   # before_save called!
    #   # before_create called!
    #   # after_create called!
    #   # after_save called!
    #
    # @deprecated
    def create(attributes = {})
      if self.class.persisted_flag_callback_control
        raise '`#create` cannot be called. The context for creation or update is determined by the `#persisted` flag.'
      end

      # steep:ignore:start
      deprecator.warn(
        'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
        'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
        '(Alternatively, exclude statements that set `false`)',
      )
      # steep:ignore:end

      assign_attributes(attributes)
      return false if invalid?

      with_transaction_returning_status do
        with_callbacks(context: :create) { save_models(bang: false) }
      rescue ActiveRecord::RecordInvalid
        false
      end
    end

    # Behavior is same to `#create`, but raises an exception prematurely on failure.
    #
    # @deprecated
    def create!(attributes = {})
      if self.class.persisted_flag_callback_control
        raise '`#create` cannot be called. The context for creation or update is determined by the `#persisted` flag.'
      end

      # steep:ignore:start
      deprecator.warn(
        'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
        'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
        '(Alternatively, exclude statements that set `false`)',
      )
      # steep:ignore:end

      assign_attributes(attributes)
      valid? || raise_validation_error

      with_transaction_returning_status do
        with_callbacks(context: :create) { save_models(bang: true) }
      end || raise_on_save_error
    end

    # Behavior is same to `#save`, but `before_update` and `after_update` hooks fires.
    #
    #   class ComposedModel < ActiveRecordCompose::Model
    #     # ...
    #
    #     before_save { puts 'before_save called!' }
    #     before_create { puts 'before_create called!' }
    #     before_update { puts 'before_update called!' }
    #     after_save { puts 'after_save called!' }
    #     after_create { puts 'after_create called!' }
    #     after_update { puts 'after_update called!' }
    #   end
    #
    #   model = ComposedModel.new
    #
    #   model.save
    #   # before_save called!
    #   # after_save called!
    #
    #   model.update
    #   # before_save called!
    #   # before_update called!
    #   # after_update called!
    #   # after_save called!
    #
    # @return [Boolean] returns true on success, false on failure.
    def update(attributes = {})
      assign_attributes(attributes)
      return false if invalid?

      with_transaction_returning_status do
        if self.class.persisted_flag_callback_control
          with_callbacks { save_models(bang: false) }
        else
          # steep:ignore:start
          deprecator.warn(
            'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
            'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
            '(Alternatively, exclude statements that set `false`)',
          )
          # steep:ignore:end
          with_callbacks(context: :update) { save_models(bang: false) }
        end
      rescue ActiveRecord::RecordInvalid
        false
      end
    end

    # Behavior is same to `#update`, but raises an exception prematurely on failure.
    #
    def update!(attributes = {})
      assign_attributes(attributes)
      valid? || raise_validation_error

      with_transaction_returning_status do
        if self.class.persisted_flag_callback_control
          with_callbacks { save_models(bang: true) }
        else
          # steep:ignore:start
          deprecator.warn(
            'The behavior with `persisted_flag_callback_control` set to `false` will be removed in 0.9.0. ' \
            'Use `self.persisted_flag_callback_control = true` set to `true`. ' \
            '(Alternatively, exclude statements that set `false`)',
          )
          # steep:ignore:end
          with_callbacks(context: :update) { save_models(bang: true) }
        end
      end || raise_on_save_error
    end

    # Returns true if model is persisted.
    #
    # By overriding this definition, you can control the callbacks that are triggered when a save is made.
    # For example, returning false will trigger before_create, around_create and after_create,
    # and returning true will trigger before_update, around_update and after_update.
    #
    # @return [Boolean] returns true if model is persisted.
    def persisted? = super

    private

    def models = @__models ||= ActiveRecordCompose::ComposedCollection.new(self)

    def validate_models
      models.__wrapped_models.lazy.select { _1.invalid? }.each { errors.merge!(_1) }
    end

    def with_callbacks(context: nil, &block)
      run_callbacks(:save) { run_callbacks(callback_context(context:), &block) }
    end

    def callback_context(context: nil)
      context || (persisted? ? :update : :create)
    end

    def save_models(bang:)
      models.__wrapped_models.all? { bang ? _1.save! : _1.save }
    end

    def raise_validation_error = raise ActiveRecord::RecordInvalid, self

    def raise_on_save_error = raise ActiveRecord::RecordNotSaved.new(raise_on_save_error_message, self)

    def raise_on_save_error_message = 'Failed to save the model.'

    def deprecator
      if ActiveRecord.respond_to?(:deprecator)
        ActiveRecord.deprecator # steep:ignore
      else # for rails 7.0.x or lower
        ActiveSupport::Deprecation
      end
    end
  end
end
