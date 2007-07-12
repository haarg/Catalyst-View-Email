package Catalyst::View::Email::Template;

use warnings;
use strict;

use Class::C3;
use Carp;

use Email::MIME::Creator;

use base qw|Catalyst::View::Email|;

our $VERSION = '0.02';

=head1 NAME

Catalyst::View::Email::Template - Send Templated Email from Catalyst

=head1 SYNOPSIS

Sends Templated mail, based upon your Default View.  Will capture the output
of the rendering path, slurps in based on mime-types and assembles a multi-part
email and sends it out.

=head2 CONFIGURATION

    View::Email::Template:
        # Set it up so if you have multiple parts, they're alternatives.
        # This is on the top-level message, not the individual parts.
        content_type: multipart/alternative
        # Optional prefix to look somewhere under the existing configured
        # template  paths.
        template_prefix: email
        # Where to look in the stash for the email information
        stash_key: email
        # Setup how to send the email
        sender:
            method:     SMTP
            host:       smtp.myhost.com
            username:   username
            password:   password

=head1 SENDING EMAIL

Sending email is just setting up your stash key, and forwarding to the view.

    $c->stash->{email} = {
        to      => 'jshirley@gmail.com',
        from    => 'no-reply@foobar.com',
        subject => 'I am a Catalyst generated email',
        # Specify which templates to include
        templates => [
            qw{text_plain/test.tt},
            qw{text_html/test.tt}
        ]
    };
    $c->forward('View::Email::Template');

If it fails $c->error will have the error message.

=cut

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
# TODO: Make this unretarded.
#
sub process {
    my ( $self, $c ) = @_;

    my $stash_key       = $self->config->{stash_key} || 'email';

    croak "No template specified for rendering"
        unless $c->stash->{$stash_key}->{template} or
                $c->stash->{$stash_key}->{templates};

    # Where to look
    my $template_prefix = $self->config->{template_prefix};
    my @templates = ();
    if ( $c->stash->{$stash_key}->{templates} ) {
        push @templates, map {
            join('/', $template_prefix, $_);
        } @{$c->stash->{$stash_key}->{templates}};

    } else {
        push @templates, join('/', $template_prefix,
            $c->stash->{$stash_key}->{template});
    }
   
    my $default_view = $c->view( $self->config->{default_view} );

    unless ( $default_view->can('render') ) {
        croak "Email::Template's configured view does not have a render method!";
    }

    #$c->log->_dump($default_view->config);

    my @parts = (); 
    foreach my $template ( @templates ) {
        $template =~ s#^/+##; # Make sure that we don't have an absolute path.
        # This seems really stupid to me... argh.  will give me nightmares!
        my $template_path = $template;
            $template_path =~ s#^$template_prefix/##;
        my ( $content_type, $extra ) = split('/', $template_path);
        if ( $extra ) {
            $content_type ||= 'text/plain';
            $content_type =~  s#_#/#;
        } else {
            $content_type = 'text/plain';
        }
        my $output = $default_view->render( $c, $template,
            { content_type => $content_type, %{$c->stash} });
        # Got a ref, not a scalar.  An error!
        if ( ref $output ) {
            croak $output->can("as_string") ? $output->as_string : $output;
        }
        push @parts, Email::MIME->create(
            attributes => {
                content_type => $content_type
            },
            body => $output
        );
    }
    delete $c->stash->{email}->{body};
    $c->stash->{email}->{parts} ||= [];
    push @{$c->stash->{email}->{parts}}, @parts;

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

=head1 LICENSE

This library is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;

