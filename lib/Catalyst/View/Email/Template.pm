package Catalyst::View::Email::Template;

use warnings;
use strict;

use Class::C3;
use Carp;
use Scalar::Util qw( blessed );

use Email::MIME::Creator;

use base qw|Catalyst::View::Email|;

our $VERSION = '0.07';

=head1 NAME

Catalyst::View::Email::Template - Send Templated Email from Catalyst

=head1 SYNOPSIS

Sends Templated mail, based upon your Default View.  Will capture the output
of the rendering path, slurps in based on mime-types and assembles a multi-part
email and sends it out.
It uses Email::MIME to create the mail.

=head2 CONFIGURATION

    View::Email::Template:
        # Optional prefix to look somewhere under the existing configured
        # template  paths. Default is none.
        template_prefix: email
        # Where to look in the stash for the email information.
        # 'email' is the default, so you don't have to specify it.
        stash_key: email
        # Define the defaults for the mail
        default:
            # Defines the default content type (mime type) for every template.
            content_type: text/html
            # Defines the default charset for every MIME part with the content
            # type 'text'.
            # According to RFC2049 such a MIME part without a charset should
            # be treated as US-ASCII by the mail client.
            # If the charset is not set it won't be set for all MIME parts
            # without an overridden one.
            charset: utf-8
            # Defines the default view which is used to render the templates.
            view: TT
        # Setup how to send the email
        # all those options are passed directly to Email::Send
        sender:
            mailer: SMTP
            mailer_args:
                Host:       smtp.example.com # defaults to localhost
                username:   username
                password:   password

=head1 SENDING EMAIL

Sending email is just setting up your defaults, the stash key and forwarding to the view.

    $c->stash->{email} = {
        to      => 'jshirley@gmail.com',
        from    => 'no-reply@foobar.com',
        subject => 'I am a Catalyst generated email',
        template => 'test.tt',
    };
    $c->forward('View::Email::Template');

Alternatively if you want more control over your templates you can use the following idiom
to override the defaults:

    templates => [
        {
            template        => 'email/test.html.tt',
            content_type    => 'text/html',
            view            => 'TT', 
        },
        {
            template        => 'email/test.plain.mason',
            content_type    => 'text/plain',
            view            => 'Mason', 
        }
    ]


If it fails $c->error will have the error message.

=cut

# here the defaults of Catalyst::View::Email are extended by the additional
# ones Template.pm needs.

__PACKAGE__->config(
    template_prefix => '',
);


# This view hitches into your default view and will call the render function
# on the templates provided.  This means that you have a layer of abstraction
# and you aren't required to modify your templates based on your desired engine
# (Template Toolkit or Mason, for example).  As long as the view adequately
# supports ->render, all things are good.  Mason, and others, are not good.

#
# The path here is to check configuration for the template root, and then
# proceed to call render on the subsequent templates and stuff each one
# into an Email::MIME container.  The mime-type will be stupidly guessed with
# the subdir on the template.
#

# Set it up so if you have multiple parts, they're alternatives.
# This is on the top-level message, not the individual parts.
#multipart/alternative

sub _validate_view {
    my ($self, $view) = @_;
    
    croak "Email::Template's configured view '$view' isn't an object!"
        unless (blessed($view));

    croak "Email::Template's configured view '$view' isn't an Catalyst::View!"
        unless ($view->isa('Catalyst::View'));

    croak "Email::Template's configured view '$view' doesn't have a render method!"
        unless ($view->can('render'));
}

sub _generate_part {
    my ($self, $c, $attrs) = @_;
    
    my $template_prefix         = $self->{template_prefix};
    my $default_view            = $self->{default}->{view};
    my $default_content_type    = $self->{default}->{content_type};

    my $view = $c->view($attrs->{view} || $default_view);
    # validate the per template view
    $self->_validate_view($view);
#    $c->log->debug("VIEW: $view");
    
    # prefix with template_prefix if configured
    my $template = $template_prefix ne '' ? join('/', $template_prefix, $attrs->{template}) : $attrs->{template};
            
    my $content_type = $attrs->{content_type} || $default_content_type;
    
    # render the email part
    my $output = $view->render( $c, $template, { 
        content_type    => "$content_type",
        stash_key       => $self->stash_key,
	%{$c->stash},
    });
				
    if (ref $output) {
	croak $output->can('as_string') ? $output->as_string : $output;
    }
	
    return Email::MIME->create(
        attributes => {
	    content_type => "$content_type",
	},
	body => $output,
    );
}

sub process {
    my ( $self, $c ) = @_;

    # validate here so _generate_part doesn't have to do it for every part
    my $stash_key = $self->{stash_key};
    croak "Email::Template's stash_key isn't defined!"
        if ($stash_key eq '');
    
    # don't validate template_prefix

    # the default view is validated on use later anyways...
    # but just to be sure even if not used
#    $self->_validate_view($c->view($self->{default}->{view}));

#    $c->log->debug("SELF: $self");
#    $c->log->debug('DEFAULT VIEW: ' . $self->{default}->{view});

    # the content type should be validated by Email::MIME::Creator

    croak "No template specified for rendering"
        unless $c->stash->{$stash_key}->{template}
            or $c->stash->{$stash_key}->{templates};
    
    # this array holds the Email::MIME objects
    # in case of the simple api only one
    my @parts = (); 

    # now find out if the single or multipart api was used
    # prefer the multipart one
    
    # multipart api
    if ($c->stash->{$stash_key}->{templates}
        && ref $c->stash->{$stash_key}->{templates} eq 'ARRAY'
        && ref $c->stash->{$stash_key}->{templates}[0] eq 'HASH') {
        # loop through all parts of the mail
        foreach my $part (@{$c->stash->{$stash_key}->{templates}}) {
            push @parts, $self->_generate_part($c, {
                view            => $part->{view},
                template        => $part->{template},
                content_type    => $part->{content_type},
            });
	}
    }
    # single part api
    elsif($c->stash->{$stash_key}->{template}) {
        push @parts, $self->_generate_part($c, {
            template    => $c->stash->{$stash_key}->{template},
        });
    }
    
    delete $c->stash->{$stash_key}->{body};
    $c->stash->{$stash_key}->{parts} ||= [];
    push @{$c->stash->{$stash_key}->{parts}}, @parts;

    # Let C::V::Email do the actual sending.  We just assemble the tasty bits.
    return $self->next::method($c);
}

=head1 TODO

=head2 ATTACHMENTS

There needs to be a method to support attachments.  What I am thinking is
something along these lines:

    attachments => [
        # Set the body to a file handle object, specify content_type and
        # the file name. (name is what it is sent at, not the file)
        { body => $fh, name => "foo.pdf", content_type => "application/pdf" },
        # Or, specify a filename that is added, and hey, encoding!
        { filename => "foo.gif", name => "foo.gif", content_type => "application/pdf", encoding => "quoted-printable" },
        # Or, just a path to a file, and do some guesswork for the content type
        "/path/to/somefile.pdf",
    ]

=head1 SEE ALSO

=head2 L<Catalyst::View::Email> - Send plain boring emails with Catalyst

=head2 L<Catalyst::Manual> - The Catalyst Manual

=head2 L<Catalyst::Manual::Cookbook> - The Catalyst Cookbook

=head1 AUTHORS

J. Shirley <jshirley@gmail.com>

Simon Elliott <cpan@browsing.co.uk>

Alexander Hartmaier <alex_hartmaier@hotmail.com>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
