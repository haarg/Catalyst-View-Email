use strict;
use warnings;
use Test::More;

use Email::Send::Test;
use FindBin;
use lib "$FindBin::Bin/lib";

eval "use Catalyst::View::TT";
if ( $@ ) {
    plan skip_all => 'Catalyst::View::TT required for Template tests';
    exit;
}
plan tests => 11;

use_ok('Catalyst::Test', 'TestApp');

my $response;
my $time = time;
ok( ( $response = request("/template_email?time=$time"))->is_success,
    'request ok' );
like( $response->content, qr/Template Email Ok/, 'controller says ok' );
my @emails = Email::Send::Test->emails;

cmp_ok(@emails, '==', 1, 'got emails');
isa_ok( $emails[0], 'Email::MIME', 'email is ok' );

like($emails[0]->content_type, qr#^multipart/alternative#, 'Multipart email');

my @parts = $emails[0]->parts;
cmp_ok(@parts, '==', 2, 'got parts');

is($parts[0]->content_type, 'text/plain; charset="us-ascii"', 'text/plain part ok');
like($parts[0]->body, qr/test-email\@example.com on $time/, 'got content back');

is($parts[1]->content_type, 'text/html; charset="us-ascii"', 'text/html ok');
like($parts[1]->body, qr{<em>test-email\@example.com</em> on $time}, 'got content back');
#like($emails[0]->body, qr/$time/, 'Got our email');

