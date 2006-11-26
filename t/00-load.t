#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'SOAP::Amazon::S3' );
}

diag( "Testing SOAP::Amazon::S3 $SOAP::Amazon::S3::VERSION, Perl $], $^X" );
