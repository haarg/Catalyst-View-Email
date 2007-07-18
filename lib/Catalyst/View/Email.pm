package Catalyst::View::Email;

use warnings;
use strict;

use Class::C3;
use Carp;

use Email::Send;
use Email::MIME::Creator;

use base qw|Catalyst::View|;

our $VERSION = '0.04';

__PACKAGE__->mk_accessors(qw(sender stash_key content_type mailer));

=head1 NAME

Catalyst::View::Email - Send Email from Catalyst

=head1 SYNOPSIS

This module simply sends out email from a stash key specified in the
configuration settings.

=head1 CONFIGURATION

In your app configuration (example in L<YAML>):

    View::Email:
        stash_key: email
        content_type: text/plain 
        sender:
            method:     SMTP
            # mailer_args is passed directly into Email::Send 
            mailer_args:
                - Host:       smtp.example.com
                - username:   username
                - password:   password

=cut

__PACKAGE__->config(
    stash_key => 'email',
);

=head1 SENDING EMAIL

In your controller, simply forward to the view after populating the C<stash_key>

    sub controller : Private {
        my ( $self, $c ) = @_;
        $c->stash->{email} = {
            to      => q{catalyst@rocksyoursocks.com},
            from    => q{no-reply@socksthatarerocked.com},
            subject => qq{Your Subject Here},
            body    => qq{Body Body Body}
        };
        $c->forward('View::Email');
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
    
    $c->forward('View::Email');
    if ( scalar( @{ $c->error } ) ) {
        $c->error(0); # Reset the error condition if you need to
        $c->res->body('Oh noes!');
    } else {
        $c->res->body('Email sent A-OK! (At least as far as we can tell)');
    }

=head1 OTHER MAILERS

Now, it's no fun to just send out email using plain strings.  We also
have L<Catalyst::View::Email::Template> for use.  You can also toggle
this as being used by setting up your configuration to look like this:

    View::Email:
        default_view: TT

Then, Catalyst::View::Email will forward to your View::TT by default.

=cut

sub new {
    my $self = shift->next::method(@_);

    my ( $c, $arguments ) = @_;

    my $mailer = Email::Send->new;

    if ( my $method = $self->sender->{method} ) {
        croak "$method is not supported, see Email::Send"
            unless $mailer->mailer_available($method);
        $mailer->mailer($method);
    } else {
        # Default case, run through the most likely options first.
        for ( qw/SMTP Sendmail Qmail/ ) {
            $mailer->mailer($_) and last if $mailer->mailer_available($_);
        }
    }

    if ( $self->sender->{mailer_args} ) {
        $mailer->mailer_args($self->sender->{mailer_args});
    }

    $self->mailer($mailer);

    return $self;
}

sub process {
    my ( $self, $c ) = @_;

    croak "Unable to send mail, bad mail configuration"
        unless $self->mailer;

    my $email  = $c->stash->{$self->stash_key};
    croak "Can't send email without a valid email structure"
        unless $email;
    
    if ( $self->content_type ) {
        $email->{content_type} ||= $self->content_type;
    }

    my $header  = $email->{header} || [];
        push @$header, ('To' => delete $email->{to})
            if $email->{to};
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

    my $message = Email::MIME->create(%mime);

    if ( $message ) {
        $self->mailer->send($message);
    } else {
        croak "Unable to create message";
    }
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

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
