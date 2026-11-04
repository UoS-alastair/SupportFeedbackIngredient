package EPrints::Plugin::SupportFeedbackIngredient;

use EPrints::Plugin;
use EPrints::Time;
use JSON;
use File::Copy ();
use File::Temp ();
use POSIX ();

our @ISA = qw/ EPrints::Plugin /;

sub new
{
    my( $class, %params ) = @_;
    my $self = $class->SUPER::new( %params );

    $self->{name} = "Feedback Widget Endpoint Handler";
    $self->{visible} = "API";

    return $self;
}

sub is_permitted
{
    my( $self, $repository ) = @_;

    my $user = $repository->current_user;
    return 0 unless defined $user;

    # Access is granted by any configured role or by an explicitly allowed user ID.
    foreach my $role ( @{$repository->config( "feedback_widget", "allowed_roles" ) || []} )
    {
        return 1 if $user->has_role( $role );
    }

    my %allowed_userids = map { $_ => 1 }
        @{$repository->config( "feedback_widget", "allowed_userids" ) || []};

    return $allowed_userids{$user->get_id} ? 1 : 0;
}

sub action_submit
{
    my( $self, $repository ) = @_;

    # The widget uses GET to check access even when its host page is a static file.
    if( $repository->get_request->method eq "GET" )
    {
        _send_json_response( $repository, "200 OK", {
            status => "success",
            permitted => $self->is_permitted( $repository ) ? JSON::true : JSON::false,
        } );
        return;
    }

    unless( $self->is_permitted( $repository ) )
    {
        _send_json_response( $repository, "403 Forbidden", {
            status => "error",
            message => "Not permitted",
        } );
        return;
    }

    if( $repository->get_request->method ne "POST" )
    {
        _send_json_response( $repository, "405 Method Not Allowed", {
            status => "error",
            message => "Method not allowed",
        } );
        return;
    }

    my $json_text = $repository->param( "payload" );

    unless( defined $json_text && length $json_text )
    {
        _send_json_response( $repository, "400 Bad Request", {
            status => "error",
            message => "Empty payload",
        } );
        return;
    }

    my $data = eval { decode_json($json_text) };
    if( $@ || ref( $data ) ne "HASH" )
    {
        _send_json_response( $repository, "400 Bad Request", {
            status => "error",
            message => "Invalid JSON",
        } );
        return;
    }

    # Submissions must contain the user, repository user, device, and page objects;
    # required values are scalars so they can be safely included in the email.
    unless(
        ref( $data->{user} ) eq "HASH" &&
        ref( $data->{eprintsUser} ) eq "HASH" &&
        ref( $data->{device} ) eq "HASH" &&
        ref( $data->{page} ) eq "HASH" &&
        defined $data->{eprintsUser}->{id} &&
        !ref( $data->{eprintsUser}->{id} ) &&
        defined $data->{eprintsUser}->{username} &&
        !ref( $data->{eprintsUser}->{username} ) &&
        defined $data->{eprintsUser}->{usertype} &&
        !ref( $data->{eprintsUser}->{usertype} ) &&
        defined $data->{user}->{name} &&
        !ref( $data->{user}->{name} ) &&
        defined $data->{user}->{email} &&
        !ref( $data->{user}->{email} ) &&
        defined $data->{user}->{comment} &&
        !ref( $data->{user}->{comment} ) &&
        defined $data->{device}->{os} &&
        !ref( $data->{device}->{os} ) &&
        defined $data->{device}->{browser} &&
        !ref( $data->{device}->{browser} ) &&
        defined $data->{page}->{fullUrl} &&
        !ref( $data->{page}->{fullUrl} )
    )
    {
        _send_json_response( $repository, "400 Bad Request", {
            status => "error",
            message => "Invalid payload",
        } );
        return;
    }

    my @attachments;
    my $query = $repository->get_query;
    my $screenshot = $query->upload( "screenshot" );
    if( defined $screenshot )
    {
        my $filepath = $query->tmpFileName( $screenshot );
        unless( defined $filepath && -f $filepath )
        {
            _send_json_response( $repository, "400 Bad Request", {
                status => "error",
                message => "Invalid screenshot upload",
            } );
            return;
        }
        # send_mail names attachments after their path, so copy to a properly named file
        my $dir = File::Temp::tempdir( CLEANUP => 1 );
        my $named = "$dir/screenshot." . _image_extension( $filepath );
        unless( File::Copy::copy( $filepath, $named ) )
        {
            _send_json_response( $repository, "500 Internal Server Error", {
                status => "error",
                message => "Unable to process screenshot",
            } );
            return;
        }
        push @attachments, $named;
    }

    # Build the email as an XML fragment because EPrints::Email::send_mail expects
    # a DOM message; text nodes keep submitted values from becoming markup.
    my $admin_email = $repository->config( "feedback_widget", "feedback_contact_email" );

    my $xml = $repository->xml;
    my $body = $xml->create_document_fragment;
    my $text = sub {
        my( $value ) = @_;
        return "" unless defined $value;
        return JSON->new->canonical->encode( $value ) if ref $value;
        return "$value";
    };
    my $query_params = $data->{page}->{queryParams};
    my @now = gmtime;
    my $timestamp = EPrints::Time::utc_datetime();
    # Include the reference in both email and logs so a submission can be traced.
    my $reference = sprintf( "FB-%s-%05d-%06X",
        POSIX::strftime( "%Y%m%d-%H%M%S", @now ),
        $$ % 100000,
        int( rand( 0xFFFFFF ) ) );
    my @lines = (
        [ "Reference", $reference ],
        [ "Submitted", $timestamp ],
        [ "Name", $text->( $data->{user}->{name} ) ],
        [ "Email", $text->( $data->{user}->{email} ) ],
        [ "EPrints user ID", $text->( $data->{eprintsUser}->{id} ) ],
        [ "EPrints username", $text->( $data->{eprintsUser}->{username} ) ],
        [ "EPrints user type", $text->( $data->{eprintsUser}->{usertype} ) ],
        [ "OS", $text->( $data->{device}->{os} ) ],
        [ "Browser", $text->( $data->{device}->{browser} ) ],
        [ "User agent", $text->( $data->{device}->{userAgent} ) ],
        [ "Screen resolution", $text->( $data->{device}->{screenResolution} ) ],
        [ "Viewport size", $text->( $data->{device}->{viewportSize} ) ],
        [ "Device pixel ratio", $text->( $data->{device}->{devicePixelRatio} ) ],
        [ "URL", $text->( $data->{page}->{fullUrl} ) ],
        [ "Path", $text->( $data->{page}->{pathname} ) ],
        [ "Query parameters", ( ref( $query_params ) eq "HASH" && %{$query_params} ) ? $text->( $query_params ) : "" ],
    );

    my $intro = $body->appendChild( $xml->create_element( "p" ) );
    $intro->appendChild( $xml->create_text_node( "New feedback submitted:" ) );

    my $details = $body->appendChild( $xml->create_element( "p" ) );
    foreach my $i ( 0 .. $#lines )
    {
        $details->appendChild( $xml->create_element( "br" ) ) if $i;
        $details->appendChild( $xml->create_text_node( "$lines[$i][0]: $lines[$i][1]" ) );
    }

    my $comment_label = $body->appendChild( $xml->create_element( "p" ) );
    $comment_label->appendChild( $xml->create_text_node( "Comment:" ) );

    my $comment = $body->appendChild( $xml->create_element( "p" ) );
    my @comment_lines = split /\r?\n/, $data->{user}->{comment}, -1;
    foreach my $i ( 0 .. $#comment_lines )
    {
        $comment->appendChild( $xml->create_element( "br" ) ) if $i;
        $comment->appendChild( $xml->create_text_node( $comment_lines[$i] ) );
    }

    my %mail_params = (
        session => $repository,
        langid => $repository->get_langid,
        to_email => $admin_email,
        subject => "[EPrints Feedback] [$reference] Submission from " . $data->{user}->{name},
        message => $body,
    );
    $mail_params{attach} = \@attachments if @attachments;

    unless( EPrints::Email::send_mail( %mail_params ) )
    {
        $repository->log( "SupportFeedbackIngredient: failed to send feedback $reference from user "
            . $data->{eprintsUser}->{username} . " (" . $data->{user}->{email} . ")" );
        _send_json_response( $repository, "500 Internal Server Error", {
            status => "error",
            message => "Unable to send feedback, please try again later.",
        } );
        return;
    }

    $repository->log( "SupportFeedbackIngredient: sent feedback $reference from user "
        . $data->{eprintsUser}->{username} . " (" . $data->{user}->{email} . ") page "
        . $data->{page}->{fullUrl} );

    _send_json_response( $repository, "200 OK", {
        status => "success",
        reference => $reference,
    } );
}

sub _image_extension
{
    my( $filepath ) = @_;

    # Identify the file from its signature rather than trusting the uploaded name.
    open( my $fh, "<:raw", $filepath ) or return "png";
    read( $fh, my $head, 12 );
    close $fh;

    return "png" if $head =~ /^\x89PNG/;
    return "jpg" if $head =~ /^\xFF\xD8\xFF/;
    return "gif" if $head =~ /^GIF8/;
    return "webp" if $head =~ /^RIFF.{4}WEBP/s;
    return "bmp" if $head =~ /^BM/;
    return "png";
}

sub _send_json_response
{
    my( $repository, $status, $response ) = @_;

    $repository->send_http_header(
        status => $status,
        content_type => "application/json",
    );
    print encode_json( $response );
}

1;

=head1 NAME

EPrints::Plugin::SupportFeedbackIngredient - feedback widget endpoint handler

=head1 DESCRIPTION

Handles the feedback widget's permission checks and submissions. Authorized
submissions are emailed to the configured feedback contact, optionally with a
screenshot attachment.

=head1 CONFIGURATION

The endpoint reads these repository settings from the C<feedback_widget>
configuration group:

=over 4

=item C<allowed_roles>

An array of EPrints roles allowed to use the widget. A user needs any one of
these roles or an ID listed in C<allowed_userids>.

=item C<allowed_userids>

An array of user IDs allowed to use the widget, in addition to users with an
allowed role.

=item C<feedback_contact_email>

The recipient address for submitted feedback.

=back

=head1 HTTP BEHAVIOR

=over 4

=item GET

Returns JSON with C<status> set to C<success> and a boolean C<permitted> value.
The value reflects whether the current user is permitted to submit feedback.

=item POST

Requires permission and a non-empty JSON C<payload> parameter. The payload must
be an object containing C<user>, C<eprintsUser>, C<device>, and C<page> objects.
Required scalar fields are the submitter's C<name>, C<email>, and C<comment>;
the repository user's C<id>, C<username>, and C<usertype>; device C<os> and
C<browser>; and page C<fullUrl>. An optional C<screenshot> upload is attached
to the email when present.

Successful submissions return C<status> C<success> and a C<reference> used to
identify the submission in the email and repository log. Errors return
C<status> C<error> and a human-readable C<message>.

=back

=cut