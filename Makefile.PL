use 5.006;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Sub::Override',
    VERSION_FROM      => 'lib/Sub/Override.pm', # finds $VERSION
    PREREQ_PM         => {
        'Test::More'      => .47,
        'Test::Exception' => .21,
        'Sub::Uplevel'    => 0, # because I'm sick of bogus test failures
    },
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'lib/Sub/Override.pm',
       AUTHOR         => 'Curtis Poe <eop_divo_sitruc@yahoo.com>') : ()),
);

# reverse the email name to get my email address
