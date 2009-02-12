use inc::Module::Install;

name 'Catalyst-View-Email';
all_from 'lib/Catalyst/View/Email.pm';

requires 'Catalyst'             => '5.7';
requires 'Class::C3';
requires 'parent';
requires 'Email::Send'          => '2.185';
requires 'Email::MIME'          => '1.859';
requires 'Email::MIME::Creator' => '1.455';

feature 'Template Toolkit Support',
    -default => 1,
    'Catalyst::View::TT' => 0;

feature 'Mason Support',
    -default => 0,
    'Catalyst::View::Mason';

feature 'Net::SMTP Support',
    -default => 0,
    'MIME::Base64',
    'Authen::SASL';

auto_install;
WriteAll;
