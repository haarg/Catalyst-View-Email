use strict;
use warnings;
use Test::More;

use Email::Send::Test;
use FindBin;
use lib "$FindBin::Bin/lib";

eval "use Catalyst::View::Mason";
if ( $@ ) {
    plan skip_all => 'Catalyst::View::Mason required for Mason tests';
    exit;
}
plan tests => 10;

use_ok('Catalyst::Test', 'TestApp');

TestApp->config->{default_view} = 'Mason';

my $response;
my $time = time;
ok( ( $response = request("/mason_email?time=$time"))->is_success,
    'request ok' );
like( $response->content, qr/Mason Email Ok/, 'controller says ok' );
my @emails = Email::Send::Test->emails;

cmp_ok(@emails, '==', 1, 'got emails');
isa_ok( $emails[0], 'Email::MIME', 'email is ok' );
my @parts = $emails[0]->parts;
cmp_ok(@parts, '==', 2, 'got parts');

is($parts[0]->content_type, 'text/plain', 'text/plain ok');
like($parts[0]->body, qr/test-email\@example.com on $time/, 'got content back');
is($parts[1]->content_type, 'text/html', 'text/html ok');
like($parts[1]->body, qr{<em>test-email\@example.com</em> on $time}, 'got content back');
#like($emails[0]->body, qr/$time/, 'Got our email');

