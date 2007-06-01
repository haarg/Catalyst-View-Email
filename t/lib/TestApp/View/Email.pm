package # Hide from PAUSE
    TestApp::View::Email;

use Email::Send::Test;

use base 'Catalyst::View::Email';

__PACKAGE__->config(
    sender => {
        method => 'Test'
    },
);

1;
