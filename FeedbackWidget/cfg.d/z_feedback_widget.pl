#!/usr/bin/perl

# Enable the feedback widget ingredient
$c->{plugins}->{"FeedbackWidget"}->{params}->{disable} = 0;

# Set global endpoint
$c->{feedback_widget}->{endpoint} = '/cgi/feedback';

# Set email contact
$c->{feedback_widget}->{feedback_contact_email} = $c->{adminemail};

# Configure any roles or numeric user IDs to allow; matching either list is sufficient.
# For example: [ "admin", "editor" ] and [ 123, 456 ].
$c->{feedback_widget}->{allowed_roles} ||= [ "admin", "local_admin" ];
$c->{feedback_widget}->{allowed_userids} ||= [];
