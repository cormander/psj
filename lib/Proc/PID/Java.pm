
#
# Custom class to stat Java(tm) processes on linux
#

package Proc::PID::Java;

use strict;
use warnings;

use base 'Proc::PID';

use File::Basename;

# constructor

sub new {
	my ($class, $pid, $portsave) = @_;

	my $java = $class->SUPER::new($pid, $portsave);

	die "PID $pid is not a java process" unless "java" eq basename($java->exe);

	$java->{env} = $java->environ;

	return $java;
}

sub java_home { return shift->{env}{JAVA_HOME}; }

sub get_version { return shift->{version}; }

sub set_version {
	my ($self, $version) = @_;

	$self->{version} = $version;
}

1;

