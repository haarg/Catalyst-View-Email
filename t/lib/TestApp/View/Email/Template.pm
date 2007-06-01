package # Hide me
    TestApp::View::Email::Template;

use strict;
use base 'Catalyst::View::Email::Template';

__PACKAGE__->config(
    sender => {
        method => 'Test'
    },
    stash_key       => 'email',
    template_prefix => ''
);

1;
