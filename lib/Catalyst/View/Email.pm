package Catalyst::View::Email;

use warnings;
use strict;

use Class::C3;
use Carp;

use Email::Send;
use Email::MIME::Creator;

use base qw/ Catalyst::View /;

our $VERSION = '0.09999_02';

__PACKAGE__->mk_accessors(qw/ mailer /);

=head1 NAME

Catalyst::View::Email - Send Email from Catalyst

=head1 SYNOPSIS

This module simply sends out email from a stash key specified in the
configuration settings.

=head1 CONFIGURATION

Use the helper to create your View:
    
    $ script/myapp_create.pl view Email Email

In your app configuration (example in L<YAML>):

    View::Email:
        # Where to look in the stash for the email information.
        # 'email' is the default, so you don't have to specify it.
        stash_key: email
        # Define the defaults for the mail
        default:
            # Defines the default content type (mime type).
            # mandatory
            content_type: text/plain
            # Defines the default charset for every MIME part with the content
            # type text.
            # According to RFC2049 a MIME part without a charset should
            # be treated as US-ASCII by the mail client.
            # If the charset is not set it won't be set for all MIME parts
            # without an overridden one.
            # Default: none
            charset: utf-8
        # Setup how to send the email
        # all those options are passed directly to Email::Send
        sender:
            mailer: SMTP
            # mailer_args is passed directly into Email::Send 
            mailer_args:
                Host:       smtp.example.com # defaults to localhost
                username:   username
                password:   password

=head2 NOTE ON SMTP

If you use SMTP and don't specify Host, it will default to localhost and
attempt delivery.  This often times means an email will sit in a queue
somewhere and not be delivered.

=cut

__PACKAGE__->config(
    stash_key   => 'email',
    default     => {
        content_type    => 'text/html',
    },
);

=head1 SENDING EMAIL

In your controller, simply forward to the view after populating the C<stash_key>

    sub controller : Private {
        my ( $self, $c ) = @_;
        $c->stash->{email} = {
            to      => q{catalyst@rocksyoursocks.com},
            cc      => q{foo@bar.com},
            bcc     => q{hidden@secret.com},
            from    => q{no-reply@socksthatarerocked.com},
            subject => qq{Your Subject Here},
            body    => qq{Body Body Body}
        };
        $c->forward( $c->view('Email' ) );
    }

Alternatively, you can use a more raw interface, and specify the headers as
an array reference.

    $c->stash->{email} = {
        header => [
            To      => 'foo@bar.com',
            Subject => 'Note the capitalization differences'
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
                body => qq{Got a body, but didn't get ahead.}
            )
        ],
    };

=head1 HANDLING FAILURES

If the email fails to send, the view will die (throw an exception).  After
your forward to the view, it is a good idea to check for errors:
    
    $c->forward( $c->view('Email' ) );
    if ( scalar( @{ $c->error } ) ) {
        $c->error(0); # Reset the error condition if you need to
        $c->res->body('Oh noes!');
    } else {
        $c->res->body('Email sent A-OK! (At least as far as we can tell)');
    }

=head1 USING TEMPLATES FOR EMAIL

Now, it's no fun to just send out email using plain strings.
Take a look at L<Catalyst::View::Email::Template> to see how you can use your
favourite template engine to render the mail body.


=cut

sub new {
    my $self = shift->next::method(@_);

    my ( $c, $arguments ) = @_;
    
    my $stash_key = $self->{stash_key};
    croak "$self stash_key isn't defined!"
        if ($stash_key eq '');

    my $sender = Email::Send->new;

    if ( my $mailer = $self->{sender}->{mailer} ) {
        croak "$mailer is not supported, see Email::Send"
            unless $sender->mailer_available($mailer);
        $sender->mailer($mailer);
    } else {
        # Default case, run through the most likely options first.
        for ( qw/SMTP Sendmail Qmail/ ) {
            $sender->mailer($_) and last if $sender->mailer_available($_);
        }
    }

    if ( my $args = $self->{sender}->{mailer_args} ) {
        if ( ref $args eq 'HASH' ) {
            $sender->mailer_args([ %$args ]);
        }
        elsif ( ref $args eq 'ARRAY' ) {
            $sender->mailer_args($args);
        } else {
            croak "Invalid mailer_args specified, check pod for Email::Send!";
        }
    }

    $self->mailer($sender);

    return $self;
}

=head2 process

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

    if ( exists $self->{content_type} ) {
        $email->{content_type} ||= $self->{content_type};
    }

    my $header  = $email->{header} || [];
        push @$header, ('To' => delete $email->{to})
            if $email->{to};
        push @$header, ('Cc' => delete $email->{cc})
            if $email->{cc};
        push @$header, ('Bcc' => delete $email->{bcc})
            if $email->{bcc};
        push @$header, ('From' => delete $email->{from})
            if $email->{from};
        push @$header, ('Subject' => delete $email->{subject})
            if $email->{subject};
        push @$header, ('Content-type' => delete $email->{content_type})
            if $email->{content_type};

    my $parts = $email->{parts};
    my $body  = $email->{body};
   
    unless ( $parts or $body ) {
        croak "Can't send email without parts or body, check stash";
    }

    my %mime = ( header => $header );

    if ( $parts and ref $parts eq 'ARRAY' ) {
        $mime{parts} = $parts;
    } else {
        $mime{body} = $body;
    }
    
    if ( $mime{attributes} and not $mime{attributes}->{charset} and
         $self->{default}->{charset} )
    {
        $mime{attributes}->{charset} = $self->{default}->{charset};
    }

    my $message = $self->generate_message( $c, \%mime );

    #my $message = Email::MIME->create(%mime);

    if ( $message ) {
        my $return = $self->mailer->send($message);
        croak "$return" if !$return;
    } else {
        croak "Unable to create message";
    }
}

=head2 setup_attributes

Merge attributes with the configured defaults.  You can override this method to
return a structure to pass into L<generate_message> which subsequently
passes the return value of this method to Email::MIME->create under the
C<attributes> key.

=cut

sub setup_attributes {
    my ( $self, $c, $attrs ) = @_;
    
    my $default_content_type    = $self->{default}->{content_type};
    my $default_charset         = $self->{default}->{charset};

    my $e_m_attrs = {};

    if (exists $attrs->{content_type} && defined $attrs->{content_type} && $attrs->{content_type} ne '') {
        $c->log->debug('C::V::Email uses specified content_type ' . $attrs->{content_type} . '.') if $c->debug;
        $e_m_attrs->{content_type} = $attrs->{content_type};
    }
    elsif (defined $default_content_type && $default_content_type ne '') {
        $c->log->debug("C::V::Email uses default content_type $default_content_type.") if $c->debug;
        $e_m_attrs->{content_type} = $default_content_type;
    }
   
    if (exists $attrs->{charset} && defined $attrs->{charset} && $attrs->{charset} ne '') {
        $e_m_attrs->{charset} = $attrs->{charset};
    }
    elsif (defined $default_charset && $default_charset ne '') {
        $e_m_attrs->{charset} = $default_charset;
    }

    return $e_m_attrs;
}

=head2 generate_message($c, $attr)

Generate a message part, which should be an L<Email::MIME> object and return it.

Takes the attributes, merges with the defaults as necessary and returns a
message object.

=cut

sub generate_message {
    my ( $self, $c, $attr ) = @_;

    # setup the attributes (merge with defaults)
    $attr->{attributes} = $self->setup_attributes($c, $attr->{attributes});
    return Email::MIME->create(%$attr);
}

=head1 SEE ALSO

=head2 L<Catalyst::View::Email::Template> - Send fancy template emails with Cat

=head2 L<Catalyst::Manual> - The Catalyst Manual

=head2 L<Catalyst::Manual::Cookbook> - The Catalyst Cookbook

=head1 AUTHORS

J. Shirley <jshirley@gmail.com>

=head1 CONTRIBUTORS

(Thanks!)

Matt S Trout

Daniel Westermann-Clark

Simon Elliott <cpan@browsing.co.uk>

Roman Filippov

Alexander Hartmaier <alex_hartmaier@hotmail.com>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
