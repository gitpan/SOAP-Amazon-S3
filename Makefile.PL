use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'SOAP::Amazon::S3',
    AUTHOR              => 'Alexander Karelas <karjala@karjala.org>',
    VERSION_FROM        => 'lib/SOAP/Amazon/S3.pm',
    ABSTRACT_FROM       => 'lib/SOAP/Amazon/S3.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
		'Time::Piece' => 0,
		'Digest::HMAC_SHA1' => 0,
		'MIME::Base64' => 0,
		'XML::MyXML' => 0.052,
		'SOAP::MySOAP' => 0.023,
		'Carp' => 0,
		'Data::Dumper' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'SOAP-Amazon-S3-*' },
);
