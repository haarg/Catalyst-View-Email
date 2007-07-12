use strict;
use warnings;
use Test::More tests => 5;

use Email::Send::Test;
use FindBin;
use lib "$FindBin::Bin/lib";

use_ok('Catalyst::Test', 'TestApp');

my $response;
my $time = time;
ok( ($response = request("/email_app_config?time=$time"))->is_success, 'request ok');

my @emails = Email::Send::Test->emails;

is(@emails, 1, "got emails");
isa_ok( $emails[0], 'Email::MIME', 'email is ok' );
like($emails[0]->body, qr/$time/, 'Got our email');
