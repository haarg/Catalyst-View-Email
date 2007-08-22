package # Hide from PAUSE
    TestApp;

use Catalyst;
use FindBin;

TestApp->config(
    root => "$FindBin::Bin/root",
    default_view => 'TT',
    'View::Email::AppConfig' => {
        sender => {
            method => 'Test',
        },
    },
    'View::Email::Template::AppConfig' => {
        stash_key => 'template_email',
        sender => {
            method => 'Test',
        },
    },
);

TestApp->setup;

1;
