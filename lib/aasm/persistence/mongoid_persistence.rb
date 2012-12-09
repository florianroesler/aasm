module AASM
  module Persistence
    module MongoidPersistence
      # This method:
      #
      # * extends the model with ClassMethods
      # * includes InstanceMethods
      #
      # Unless the corresponding methods are already defined, it includes
      # * ReadState
      # * WriteState
      # * WriteStateWithoutPersistence
      #
      # Adds
      #
      #   before_validation :aasm_ensure_initial_state
      #
      # As a result, it doesn't matter when you define your methods - the following 2 are equivalent
      #
      #   class Foo
      #     include Mongoid::Document
      #     def aasm_write_state(state)
      #       "bar"
      #     end
      #     include AASM
      #   end
      #
      #   class Foo
      #     include Mongoid::Document
      #     include AASM
      #     def aasm_write_state(state)
      #       "bar"
      #     end
      #   end
      #
      def self.included(base)
        base.extend AASM::Persistence::Base::ClassMethods
        base.extend AASM::Persistence::MongoidPersistence::ClassMethods
        base.send(:include, AASM::Persistence::MongoidPersistence::InstanceMethods)
        base.send(:include, AASM::Persistence::ReadState) unless base.method_defined?(:aasm_read_state)
        base.send(:include, AASM::Persistence::MongoidPersistence::WriteState) unless base.method_defined?(:aasm_write_state)
        base.send(:include, AASM::Persistence::MongoidPersistence::WriteStateWithoutPersistence) unless base.method_defined?(:aasm_write_state_without_persistence)

        # if base.respond_to?(:named_scope)
        #   base.extend(AASM::Persistence::MongoidPersistence::NamedScopeMethods)
        #
        #   base.class_eval do
        #     class << self
        #       unless method_defined?(:aasm_state_without_named_scope)
        #         alias_method :aasm_state_without_named_scope, :aasm_state
        #         alias_method :aasm_state, :aasm_state_with_named_scope
        #       end
        #     end
        #   end
        # end

        # Mongoid's Validatable gem dependency goes not have a before_validation_on_xxx hook yet.
        # base.before_validation_on_create :aasm_ensure_initial_state
        base.before_validation :aasm_ensure_initial_state
      end

      module ClassMethods
      end

      module InstanceMethods

        # Returns the current aasm_state of the object.  Respects reload and
        # any changes made to the aasm_state field directly
        #
        # Internally just calls <tt>aasm_read_state</tt>
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :pending
        #   foo.aasm_state = "opened"
        #   foo.aasm_current_state # => :opened
        #   foo.close # => calls aasm_write_state_without_persistence
        #   foo.aasm_current_state # => :closed
        #   foo.reload
        #   foo.aasm_current_state # => :pending
        #
        def aasm_current_state
          @current_state = aasm_read_state
        end

        private

        # Ensures that if the aasm_state column is nil and the record is new
        # that the initial state gets populated before validation on create
        #
        #   foo = Foo.new
        #   foo.aasm_state # => nil
        #   foo.valid?
        #   foo.aasm_state # => "open" (where :open is the initial state)
        #
        #
        #   foo = Foo.find(:first)
        #   foo.aasm_state # => 1
        #   foo.aasm_state = nil
        #   foo.valid?
        #   foo.aasm_state # => nil
        #
        def aasm_ensure_initial_state
          send("#{self.class.aasm_column}=", self.aasm_enter_initial_state.to_s) if send(self.class.aasm_column).blank?
        end

      end

      module WriteStateWithoutPersistence
        # Writes <tt>state</tt> to the state column, but does not persist it to the database
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :opened
        #   foo.close
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :opened
        #   foo.save
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :closed
        #
        # NOTE: intended to be called from an event
        def aasm_write_state_without_persistence(state)
          write_attribute(self.class.aasm_column, state.to_s)
        end
      end

      module WriteState
        # Writes <tt>state</tt> to the state column and persists it to the database
        # using update_attribute (which bypasses validation)
        #
        #   foo = Foo.find(1)
        #   foo.aasm_current_state # => :opened
        #   foo.close!
        #   foo.aasm_current_state # => :closed
        #   Foo.find(1).aasm_current_state # => :closed
        #
        # NOTE: intended to be called from an event
        def aasm_write_state(state)
          old_value = read_attribute(self.class.aasm_column)
          write_attribute(self.class.aasm_column, state.to_s)

          unless self.save(:validate => false)
            write_attribute(self.class.aasm_column, old_value)
            return false
          end

          true
        end
      end

      module NamedScopeMethods
        def aasm_state_with_named_scope name, options = {}
          aasm_state_without_named_scope name, options
          self.named_scope name, :conditions => { "#{table_name}.#{self.aasm_column}" => name.to_s} unless self.respond_to?(name)
        end
      end
    end
  end
end