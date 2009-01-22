use strict;
use warnings;
use Test::More tests => 13;

use Email::Send::Test;
use FindBin;
use lib "$FindBin::Bin/lib";

use_ok('Catalyst::Test', 'TestApp');

my $response;
my $time;
my @emails;

$time = time;

ok( ($response = request("/email_app_config?time=$time"))->is_success, 'request ok');

@emails = Email::Send::Test->emails;

is(@emails, 1, "got emails");
isa_ok( $emails[0], 'Email::MIME', 'email is ok' );
like($emails[0]->body, qr/$time/, 'Got our email');

Email::Send::Test->clear;

$time = time;
ok( ($response = request("/template_email_app_config?time=$time"))->is_success, 'request ok');

@emails = Email::Send::Test->emails;

is(@emails, 1, "got emails");
isa_ok( $emails[0], 'Email::MIME', 'email is ok' );
my @parts = $emails[0]->parts;
cmp_ok(@parts, '==', 2, 'got parts');

is($parts[0]->content_type, 'text/plain', 'text/plain ok');
like($parts[0]->body, qr/test-email\@example.com on $time/, 'got content back');
is($parts[1]->content_type, 'text/html', 'text/html ok');
like($parts[1]->body, qr{<em>test-email\@example.com</em> on $time}, 'got content back');

