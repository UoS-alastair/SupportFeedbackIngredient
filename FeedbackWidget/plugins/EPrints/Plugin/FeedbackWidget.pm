package EPrints::Plugin::FeedbackWidget;

use EPrints::Plugin;
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
    my( $plugin, $repository ) = @_;

    my $user = $repository->current_user;
    return 0 unless defined $user;

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
    my( $plugin, $repository ) = @_;

    # Lets the widget check permission on pages that are served as static files
    if( $repository->get_request->method eq "GET" )
    {
        _send_json_response( $repository, "200 OK", {
            status => "success",
            permitted => $plugin->is_permitted( $repository ) ? JSON::true : JSON::false,
        } );
        return;
    }

    unless( $plugin->is_permitted( $repository ) )
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

    # Example: Send an internal email to repository administrators
    my $admin_email = $repository->config( "feedback_widget", "feedback_contact_email" );

    # send_mail expects the message as an XML DOM tree, not a plain string
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
    my $timestamp = POSIX::strftime( "%Y-%m-%d %H:%M:%S UTC", @now );
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
        $repository->log( "FeedbackWidget: failed to send feedback $reference from user "
            . $data->{eprintsUser}->{username} . " (" . $data->{user}->{email} . ")" );
        _send_json_response( $repository, "500 Internal Server Error", {
            status => "error",
            message => "Unable to send feedback, please try again later.",
        } );
        return;
    }

    $repository->log( "FeedbackWidget: sent feedback $reference from user "
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