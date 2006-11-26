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
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'SOAP-Amazon-S3-*' },
);
