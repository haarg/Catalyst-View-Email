package Catalyst::View::Email;

use Moose;
use Carp;

use Encode qw(encode decode);
use Email::Sender::Simple qw/ sendmail /;
use Email::Simple;
use Email::Simple::Creator;

extends 'Catalyst::View';

our $VERSION = '0.13';

has 'stash_key' => (
    is      => 'rw',
	isa     => 'Str',
	lazy    => 1,
    default => sub { "email" }
);

has 'default' => (
    is      => 'rw',
	isa     => 'HashRef',
	default => sub { { content_type => 'text/plain' } },
    lazy    => 1,
);


has 'sender' => (
    is      => 'rw',
	isa     => 'HashRef',
	lazy    => 1,
    default => sub { { mailer => 'sendmail' } }
);

has 'content_type' => (
    is      => 'rw',
	isa     => 'Str',
	lazy    => 1,
	default => sub { shift->default->{'content_type'} }
);

=head1 NAME

Catalyst::View::Email - Send Email from Catalyst

=head1 SYNOPSIS

This module sends out emails from a stash key specified in the
configuration settings.

=head1 CONFIGURATION

WARNING: since version 0.10 the configuration options slightly changed!

Use the helper to create your View:
    
    $ script/myapp_create.pl view Email Email

In your app configuration:

    __PACKAGE__->config(
        'View::Email' => {
            # Where to look in the stash for the email information.
            # 'email' is the default, so you don't have to specify it.
            stash_key => 'email',
            # Define the defaults for the mail
            default => {
                # Defines the default content type (mime type). Mandatory
                content_type => 'text/plain',
                # Defines the default charset for every MIME part with the 
                # content type text.
                # According to RFC2049 a MIME part without a charset should
                # be treated as US-ASCII by the mail client.
                # If the charset is not set it won't be set for all MIME parts
                # without an overridden one.
                # Default: none
                charset => 'utf-8'
            },
            # Setup how to send the email
            # all those options are passed directly to Email::Send
            sender => {
                mailer => 'SMTP',
                # mailer_args is passed directly into Email::Send 
                mailer_args => {
                    Host     => 'smtp.example.com', # defaults to localhost
                    username => 'username',
                    password => 'password',
            }
          }
        }
    );

=head1 NOTE ON SMTP

If you use SMTP and don't specify Host, it will default to localhost and
attempt delivery. This often means an email will sit in a queue and
not be delivered.

=cut


=head1 SENDING EMAIL

Sending email is just filling the stash and forwarding to the view:

    sub controller : Private {
        my ( $self, $c ) = @_;

        $c->stash->{email} = {
            to      => 'jshirley@gmail.com',
            cc      => 'abraxxa@cpan.org',
            bcc     => join ',', qw/hidden@secret.com hidden2@foobar.com/,
            from    => 'no-reply@foobar.com',
            subject => 'I am a Catalyst generated email',
            body    => 'Body Body Body',
        };
        
        $c->forward( $c->view('Email') );
    }

Alternatively you can use a more raw interface and specify the headers as
an array reference like it is passed to L<Email::MIME::Creator>.
Note that you may also mix both syntaxes if you like ours better but need to
specify additional header attributes.
The attributes are appended to the header array reference without overwriting
contained ones.

    $c->stash->{email} = {
        header => [
            To      => 'jshirley@gmail.com',
            Cc      => 'abraxxa@cpan.org',
            Bcc     => join ',', qw/hidden@secret.com hidden2@foobar.com/,
            From    => 'no-reply@foobar.com',
            Subject => 'Note the capitalization differences',
        ],
        body => qq{Ain't got no body, and nobody cares.},
        # Or, send parts
        parts => [
            Email::MIME->create(
                attributes => {
                    content_type => 'text/plain',
                    disposition  => 'attachment',
                    charset      => 'US-ASCII',
                },
                body => qq{Got a body, but didn't get ahead.},
            )
        ],
    };

=head1 HANDLING ERRORS

If the email fails to send, the view will die (throw an exception).
After your forward to the view, it is a good idea to check for errors:
    
    $c->forward( $c->view('Email') );
    
    if ( scalar( @{ $c->error } ) ) {
        $c->error(0); # Reset the error condition if you need to
        $c->response->body('Oh noes!');
    } else {
        $c->response->body('Email sent A-OK! (At least as far as we can tell)');
    }

=head1 USING TEMPLATES FOR EMAIL

Now, it's no fun to just send out email using plain strings.
Take a look at L<Catalyst::View::Email::Template> to see how you can use your
favourite template engine to render the mail body.

=head1 METHODS

=over 4

=item new

Validates the base config and creates the L<Email::Send> object for later use
by process.

=cut
sub BUILD {
    my $self = shift;

    my $stash_key = $self->stash_key;
	croak "$self stash_key isn't defined!"
	    if ($stash_key eq '');

}

=item process($c)

The process method does the actual processing when the view is dispatched to.

This method sets up the email parts and hands off to L<Email::Send> to handle
the actual email delivery.

=cut

sub process {
    my ( $self, $c ) = @_;

    croak "Unable to send mail, bad mail configuration"
        unless $self->mailer;

    my $email  = $c->stash->{$self->{stash_key}};
    croak "Can't send email without a valid email structure"
        unless $email;

    my $header  = $email->{header} || [];
        push @$header, ('To' => delete $email->{to})
            if $email->{to};
        push @$header, ('Cc' => delete $email->{cc})
            if $email->{cc};
        push @$header, ('Bcc' => delete $email->{bcc})
            if $email->{bcc};
        push @$header, ('From' => delete $email->{from})
            if $email->{from};
        push @$header, ('Subject' => Encode::encode('MIME-Header', delete $email->{subject}))
            if $email->{subject};

    my $parts = $email->{parts};
    my $body  = $email->{body};
   
    unless ( $parts or $body ) {
        croak "Can't send email without parts or body, check stash";
    }

    my %mime = ( header => $header, attributes => {} );

    if ( $parts and ref $parts eq 'ARRAY' ) {
        $mime{parts} = $parts;
    } else {
        $mime{body} = $body;
    }

    my $message = $self->generate_message( $c, \%mime );

    if ( $message ) {
        my $return = sendmail($message);
        # return is a Return::Value object, so this will stringify as the error
        # in the case of a failure.  
        croak "$return" if !$return;
    } else {
        croak "Unable to create message";
    }
}

=item setup_attributes($c, $attr)

Merge attributes with the configured defaults. You can override this method to
return a structure to pass into L<generate_message> which subsequently
passes the return value of this method to Email::MIME->create under the
C<attributes> key.

=cut

=item generate_message($c, $attr)

Generate a message part, which should be an L<Email::MIME> object and return it.

Takes the attributes, merges with the defaults as necessary and returns a
message object.

=cut

sub generate_message {
    my ( $self, $c, $attr ) = @_;

    # setup the attributes (merge with defaults)
    return Email::Simple->create(
	    header => $attr->{header},
		body   => $attr->{body}
	);
}

=back

=head1 TROUBLESHOOTING

As with most things computer related, things break.  Email even more so.  
Typically any errors are going to come from using SMTP as your sending method,
which means that if you are having trouble the first place to look is at
L<Email::Send::SMTP>.  This module is just a wrapper for L<Email::Send>,
so if you get an error on sending, it is likely from there anyway.

If you are using SMTP and have troubles sending, whether it is authentication
or a very bland "Can't send" message, make sure that you have L<Net::SMTP> and,
if applicable, L<Net::SMTP::SSL> installed.

It is very simple to check that you can connect via L<Net::SMTP>, and if you
do have sending errors the first thing to do is to write a simple script
that attempts to connect.  If it works, it is probably something in your
configuration so double check there.  If it doesn't, well, keep modifying
the script and/or your mail server configuration until it does!

=head1 SEE ALSO

=head2 L<Catalyst::View::Email::Template> - Send fancy template emails with Cat

=head2 L<Catalyst::Manual> - The Catalyst Manual

=head2 L<Catalyst::Manual::Cookbook> - The Catalyst Cookbook

=head1 AUTHORS

J. Shirley <jshirley@gmail.com>

Alexander Hartmaier <abraxxa@cpan.org>

=head1 CONTRIBUTORS

(Thanks!)

Matt S Trout

Daniel Westermann-Clark

Simon Elliott <cpan@browsing.co.uk>

Roman Filippov

Lance Brown <lance@bearcircle.net>

=head1 COPYRIGHT

Copyright (c) 2007 - 2009
the Catalyst::View::Email L</AUTHORS> and L</CONTRIBUTORS>
as listed above.

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
