#!/usr/bin/perl

# Enable the feedback widget ingredient
$c->{plugins}->{"SupportFeedbackIngredient"}->{params}->{disable} = 0;

# Set global endpoint
$c->{SupportFeedbackIngredient}->{endpoint} = '/cgi/feedback';

# Set email contact
$c->{SupportFeedbackIngredient}->{feedback_contact_email} = $c->{adminemail};

# Configure any roles or numeric user IDs to allow; matching either list is sufficient.
# For example: [ "admin", "editor" ] and [ 123, 456 ].
$c->{SupportFeedbackIngredient}->{allowed_roles} ||= [ "admin", "local_admin" ];
$c->{SupportFeedbackIngredient}->{allowed_userids} ||= [];
