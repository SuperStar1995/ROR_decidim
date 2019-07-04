# frozen_string_literal: true

module Decidim
  # This concern contains the logic related to amendable resources.
  module Amendable
    extend ActiveSupport::Concern

    included do
      has_many :amendments,
               as: :amendable,
               foreign_key: "decidim_amendable_id",
               foreign_type: "decidim_amendable_type",
               class_name: "Decidim::Amendment"

      # resource.emendations : resources that have amended the original resource
      has_many :emendations,
               through: :amendments,
               source: :emendation,
               source_type: name,
               inverse_of: :emendations

      # resource.amenders : users that have created emendations for the original resource
      has_many :amenders,
               through: :amendments,
               source: :amender

      has_one :amended,
              as: :amendable,
              foreign_key: "decidim_emendation_id",
              foreign_type: "decidim_emendation_type",
              class_name: "Decidim::Amendment"

      # resource.amendable : the original resource that was amended
      has_one :amendable, through: :amended, source: :amendable, source_type: name

      scope :only_amendables, -> { where.not(id: joins(:amendable)) }
      scope :only_emendations, -> { where(id: joins(:amendable)) }
      # retrieves resources that are emendations and visible to the user
      # based on the component's amendments settings.
      scope :only_visible_emendations_for, lambda { |user, component|
        return only_emendations unless component.settings.amendments_enabled

        case component.current_settings.amendments_visibility
        when "participants"
          return none unless user

          where(id: joins(:amendable).where("decidim_amendments.decidim_user_id = ?", user.id))
        else # Assume 'all' or wrong value
          only_emendations
        end
      }
      # retrieves both resources that are amendables and emendations filtering out the emendations
      # that are not visible to the user based on the component's amendments settings.
      scope :amendables_and_visible_emendations_for, lambda { |user, component|
        return all unless component.settings.amendments_enabled

        case component.current_settings.amendments_visibility
        when "participants"
          return only_amendables unless user

          where.not(id: joins(:amendable).where.not("decidim_amendments.decidim_user_id = ?", user.id))
        else # Assume 'all' or wrong value
          all
        end
      }
    end

    class_methods do
      attr_reader :amendable_options
      # Public: Configures amendable for this model.
      #
      # fields  - An `Array` of `symbols` specifying the fields that can be amended
      # form    - The form used for the validation and creation of the emendation
      #
      # Returns nothing.
      def amendable(fields: nil, form: nil)
        raise "You must provide a set of fields to amend" unless fields
        raise "You must provide a form class of the amendable" unless form

        @amendable_options = { fields: fields, form: form }
      end
    end

    # Returns the fields that can be amended.
    def amendable_fields
      self.class.amendable_options[:fields]
    end

    # Returns the form used for the validation and creation of the emendation.
    def amendable_form
      self.class.amendable_options[:form].constantize
    end

    # Returns the ActiveRecord class name of the resource.
    def amendable_type
      resource_manifest.model_class_name
    end

    # Returns the polymorphic association.
    def amendment
      associated_resource = emendation? ? :emendation : :amendable

      Decidim::Amendment.find_by(associated_resource => id)
    end

    # Checks if the resource HAS amended another resource.
    # Returns true or false.
    def emendation?
      amendable.present?
    end

    # Checks if the resource CAN be amended by other resources.
    # Returns true or false.
    def amendable?
      amendable.blank?
    end

    # Returns the state of the amendment or the state of the resource.
    def state
      return amendment.state if emendation?

      attributes["state"]
    end

    # Returns the linked resource to or from this model
    # for the given resource name and link name.
    # See Decidim::Resourceable#link_resources
    def linked_promoted_resource
      linked_resources(amendable_type, "created_from_rejected_emendation").first
    end

    # Returns the emendations of an amendable that are visible to the user
    # based on the component's amendments settings.
    def visible_emendations_for(user)
      return emendations unless component.settings.amendments_enabled

      case component.current_settings.amendments_visibility
      when "participants"
        return amendable_type.constantize.none unless user

        emendations.where("decidim_amendments.decidim_user_id = ?", user.id)
      else # Assume 'all' or wrong value
        emendations
      end
    end

    # Returns the amendments (polymorphic association) of the emendations that
    # are visible to the user based on the component's amendments settings.
    def visible_amendments_for(user)
      amendments.where(emendation: visible_emendations_for(user))
    end
  end
end
