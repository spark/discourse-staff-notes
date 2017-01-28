# name: staff-notes
# about: Gives the ability for staff members to attach notes to users
# version: 0.0.3
# authors: Robin Ward

enabled_site_setting :staff_notes_enabled

register_asset 'stylesheets/staff_notes.scss'

STAFF_NOTE_COUNT_FIELD = "staff_notes_count"

after_initialize do

  require_dependency 'user'

  module ::DiscourseStaffNotes
    class Engine < ::Rails::Engine
      engine_name "discourse_staff_notes"
      isolate_namespace DiscourseStaffNotes
    end

    def self.key_for(user_id)
      "notes:#{user_id}"
    end

    def self.notes_for(user_id)
      PluginStore.get('staff_notes', key_for(user_id)) || []
    end

    def self.add_note(user, raw, created_by)
      notes = notes_for(user.id)
      record = { id: SecureRandom.hex(16), user_id: user.id, raw: raw, created_by: created_by, created_at: Time.now }
      notes << record
      ::PluginStore.set("staff_notes", key_for(user.id), notes)

      user.custom_fields[STAFF_NOTE_COUNT_FIELD] = notes.size
      user.save_custom_fields

      record
    end

    def self.remove_note(user, note_id)
      notes = notes_for(user.id)
      notes.reject! {|n| n[:id] == note_id}

      if notes.size > 0
        ::PluginStore.set("staff_notes", key_for(user.id), notes)
      else
        ::PluginStore.remove("staff_notes", key_for(user.id))
      end
      user.custom_fields[STAFF_NOTE_COUNT_FIELD] = notes.size
      user.save_custom_fields
    end

  end

  require_dependency 'application_serializer'
  class ::StaffNoteSerializer < ApplicationSerializer
    attributes :id, :user_id, :raw, :created_by, :created_at, :can_delete

    def id
      object[:id]
    end

    def user_id
      object[:user_id]
    end

    def raw
      object[:raw]
    end

    def created_by
      BasicUserSerializer.new(object[:created_by], scope: scope, root: false)
    end

    def created_at
      object[:created_at]
    end

    def can_delete
      scope.can_delete_staff_notes?
    end
  end

  require_dependency 'application_controller'
  class DiscourseStaffNotes::StaffNotesController < ::ApplicationController
    before_filter :ensure_logged_in
    before_filter :ensure_staff

    def index
      user = User.where(id: params[:user_id]).first
      raise Discourse::NotFound if user.blank?

      notes = ::DiscourseStaffNotes.notes_for(params[:user_id])
      render json: {
        extras: { username: user.username },
        staff_notes: create_json(notes)
      }
    end

    def create
      user = User.where(id: params[:staff_note][:user_id]).first
      raise Discourse::NotFound if user.blank?
      staff_note = ::DiscourseStaffNotes.add_note(user, params[:staff_note][:raw], current_user.id)

      render json: create_json(staff_note)
    end

    def destroy
      user = User.where(id: params[:user_id]).first
      raise Discourse::NotFound if user.blank?

      raise Discourse::InvalidAccess.new unless guardian.can_delete_staff_notes?

      ::DiscourseStaffNotes.remove_note(user, params[:id])
      render json: success_json
    end

    protected

      def create_json(obj)
        # Avoid n+1
        if obj.is_a?(Array)
          by_ids = {}
          User.where(id: obj.map {|o| o[:created_by] }).each do |u|
            by_ids[u.id] = u
          end
          obj.each {|o| o[:created_by] = by_ids[o[:created_by].to_i] }
        else
          obj[:created_by] = User.where(id: obj[:created_by]).first
        end

        serialize_data(obj, ::StaffNoteSerializer)
      end
  end

  whitelist_staff_user_custom_field(STAFF_NOTE_COUNT_FIELD)

  add_to_class(Guardian, :can_delete_staff_notes?) do
    (SiteSetting.staff_notes_moderators_delete? && user.staff?) || user.admin?
  end

  DiscourseStaffNotes::Engine.routes.draw do
    get '/' => 'staff_notes#index'
    post '/' => 'staff_notes#create'
    delete '/:id' => 'staff_notes#destroy'
  end

  Discourse::Application.routes.append do
    mount ::DiscourseStaffNotes::Engine, at: "/staff_notes"
  end

  add_model_callback :warning, :after_create do
    user = User.find_by_id(self.user_id)
    created_by_user = User.find_by_id(self.created_by_id)
    warning_topic = Topic.find_by_id(self.topic_id)
    raw_note = I18n.t("staff_notes.official_warning", username: created_by_user.username, warning_link: "[#{warning_topic.title}](#{warning_topic.url})")
    ::DiscourseStaffNotes.add_note(user, raw_note, Discourse::SYSTEM_USER_ID)
  end

end
