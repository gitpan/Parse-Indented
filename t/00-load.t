#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Parse::Indented' ) || print "Bail out!
";
}

diag( "Testing Parse::Indented $Parse::Indented::VERSION, Perl $], $^X" );
