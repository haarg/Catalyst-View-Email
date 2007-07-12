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
);

TestApp->setup;

1;
