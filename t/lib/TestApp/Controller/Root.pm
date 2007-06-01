package  # Hide from PAUSE
    TestApp::Controller::Root;

use base qw(Catalyst::Controller);

sub default : Private {
    my ( $self, $c ) = @_;

    $c->res->body(qq{Nothing Here});
}

sub email : Global('email') {
    my ($self, $c, @args) = @_;

    my $time = $c->req->params->{time} || time;

    $c->stash->{email} = {
        to      => 'test-email@example.com',
        from    => 'no-reply@example.com',
        subject => 'Email Test',
        body    => "Email Sent at: $time"
    };

    $c->forward('TestApp::View::Email');

    if ( scalar( @{ $c->error } ) ) {
        $c->res->status(500);
        $c->res->body('Email Failed');
    } else {
        $c->res->body('Plain Email Ok');
    }
}

sub template_email : Global('template_email') {
    my ($self, $c, @args) = @_;

    $c->stash->{time} = $c->req->params->{time} || time;

    $c->stash->{email} = {
        to      => 'test-email@example.com',
        from    => 'no-reply@example.com',
        subject => 'Just a test',
        content_type => 'multipart/alternative',
        templates => [
            qw{text_plain/test.tt},
            qw{text_html/test.tt}
        ]
    };

    $c->forward('TestApp::View::Email::Template');    

    if ( scalar( @{ $c->error } ) ) {
        $c->res->status(500);
        $c->res->body('Template Email Failed');
    } else {
        $c->res->body('Template Email Ok');
    }
}

1;
