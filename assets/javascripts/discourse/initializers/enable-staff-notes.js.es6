import { withPluginApi } from 'discourse/lib/plugin-api';
import { iconNode } from 'discourse/helpers/fa-icon-node';
import { showStaffNotes } from 'discourse/plugins/staff-notes/discourse-staff-notes/lib/staff-notes';

export default {
  name: 'enable-staff-notes',
  initialize(container) {
    const siteSettings = container.lookup('site-settings:main');
    const currentUser = container.lookup('current-user:main');
    if (!siteSettings.staff_notes_enabled || !currentUser || !currentUser.staff) { return; }

    const store = container.lookup('store:main');
    withPluginApi('0.2', api => {
      function widgetShowStaffNotes() {
        showStaffNotes(store, this.attrs.user_id, count => {
          this.sendWidgetAction('refreshStaffNotes', count);
        });
      }

      api.attachWidgetAction('post', 'refreshStaffNotes', function(count) {
        const cfs = this.model.get('user_custom_fields') || {};
        cfs.staff_notes_count = count;
        this.model.set('user_custom_fields', cfs);
      });

      const UserController = container.lookupFactory('controller:user');
      UserController.reopen({
        staffNotesCount: null,

        _modelChanged: function() {
          this.set('staffNotesCount', this.get('model.custom_fields.staff_notes_count') || 0);
        }.observes('model').on('init'),

        actions: {
          showStaffNotes() {
            const user = this.get('model');
            showStaffNotes(store, user.get('id'), count => this.set('staffNotesCount', count));
          }
        }
      });

      const mobileView = api.container.lookup('site:main').mobileView;
      const loc = mobileView ? 'before' : 'after';
      api.decorateWidget(`poster-name:${loc}`, dec => {
        const cfs = dec.attrs.userCustomFields || {};
        if (cfs.staff_notes_count > 0) {
          return dec.attach('staff-notes-icon');
        }
      });

      api.decorateWidget('post-admin-menu:after', dec => {
        return dec.attach('post-admin-menu-button', {
          icon: 'pencil',
          label: 'staff_notes.attach',
          action: 'showStaffNotes'
        });
      });

      api.attachWidgetAction('post-admin-menu', 'showStaffNotes', widgetShowStaffNotes);

      api.createWidget('staff-notes-icon', {
        tagName: 'span.staff-notes-icon',
        click: widgetShowStaffNotes,

        html() {
          return iconNode('black-tie');
        }
      });
    });
  },
};
