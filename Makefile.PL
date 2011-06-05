use 5.010001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'psj',
    VERSION_FROM      => 'bin/psj',
    PREREQ_PM         => {},
    EXE_FILES => [ "bin/psj" ],
    ($] >= 5.005 ?
      (ABSTRACT_FROM  => 'bin/psj', # retrieve abstract from module
       AUTHOR         => 'Corey Henderson <corman@cormander.com>') : ()),
);
