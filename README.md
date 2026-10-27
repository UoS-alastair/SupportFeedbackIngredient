# Support Feedback Ingredient

An EPrints ingredient that adds a floating support form for collecting feedback and page, browser, and device details from permitted users. A screenshot can also be attached. Submissions are sent by email to the configured feedback contact.

## Configuration

The ingredient's default configuration is in `FeedbackWidget/cfg.d/z_feedback_widget.pl`:

```perl
# Enable the FeedbackWidget plugin
$c->{plugins}->{"FeedbackWidget"}->{params}->{disable} = 0;

# Feedback endpoint
$c->{feedback_widget}->{endpoint} = '/cgi/feedback';

# Recipient for feedback emails
$c->{feedback_widget}->{feedback_contact_email} = $c->{adminemail};

# Users with either of these roles, or an explicitly allowed user ID, can use the widget
$c->{feedback_widget}->{allowed_roles} ||= [ "admin", "local_admin" ];
$c->{feedback_widget}->{allowed_userids} ||= [];
```

| Option | Description |
| --- | --- |
| `plugins->{FeedbackWidget}->{params}->{disable}` | Set to `0` to enable the widget plugin. |
| `feedback_widget->{endpoint}` | CGI endpoint used by the widget for its permission check and submissions. The default is `/cgi/feedback`. The same path is currently set as `ENDPOINT_URL` in `FeedbackWidget/static/javascript/auto/feedback.js`; if you change the endpoint, update both values. |
| `feedback_widget->{feedback_contact_email}` | Email address that receives submissions. The default uses the repository's `$c->{adminemail}`. |
| `feedback_widget->{allowed_roles}` | Array of EPrints roles allowed to use the widget. The default is `admin` and `local_admin`. |
| `feedback_widget->{allowed_userids}` | Array of EPrints user IDs allowed to use the widget. The default is empty. |

Access is granted when the current user has **any** configured allowed role or their ID is in `allowed_userids`. For example, to allow users with the `editor` role and user IDs `123` or `456`:

```perl
$c->{feedback_widget}->{allowed_roles} = [ "editor" ];
$c->{feedback_widget}->{allowed_userids} = [ 123, 456 ];
```

## Customising the CSS

The widget stylesheet is `FeedbackWidget/static/style/auto/feedback.css`. You can edit it directly or override its styles in a site stylesheet that loads after the widget stylesheet. Its `:root` custom properties are intended for common visual changes:

```css
:root {
    --fb-primary: #315a7d;
    --fb-on-primary: #ffffff;
    --fb-surface: #f7f9fb;
    --fb-root-offset: 24px;
    --fb-modal-width: 360px;
    --fb-radius-lg: 12px;
}
```

Available properties cover:

- **Colours:** `--fb-primary`, `--fb-on-primary`, `--fb-surface`, `--fb-text-muted`, `--fb-border-modal`, `--fb-border-input`, `--fb-border-preview`, `--fb-success-text`, `--fb-success-bg`, `--fb-error-text`, and `--fb-error-bg`.
- **Shadows:** `--fb-shadow-sm` and `--fb-shadow-lg`.
- **Position and stacking:** `--fb-root-offset`, `--fb-z-index`, and `--fb-modal-offset`.
- **Dimensions and spacing:** `--fb-size-zero`, `--fb-size-full`, `--fb-border-width`, `--fb-modal-width`, `--fb-preview-max-height`, `--fb-trigger-padding`, `--fb-submit-padding`, `--fb-space-xs`, `--fb-space-md`, `--fb-space-lg`, and `--fb-space-xl`.
- **Corners and typography:** `--fb-radius-sm`, `--fb-radius-lg`, `--fb-radius-pill`, `--fb-font-heading`, `--fb-font-close`, `--fb-font-label`, and `--fb-font-hint`.

The stylesheet also uses widget-specific selectors such as `#fb-widget-root`, `#fb-trigger-btn`, `#fb-modal`, `#fb-submit-btn`, `.fb-header`, `.fb-field`, and `.fb-message`. Override these when you need changes beyond the provided custom properties.
