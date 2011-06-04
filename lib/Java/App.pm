
package Java::App;

use strict;
use warnings;

use PSJ::Common;

use base 'Proc::PID::Java';

sub new {
	my ($class, $pid, $rpmsave, $portsave) = @_;

	my $self = $class->SUPER::new($pid, $portsave);

	$self->{tomcat} = 0;
	$self->{shared_tomcat} = 0;
	$self->{packages} = [];

	$self->pkg_search($rpmsave);

	# check to see if this is shared tomcat
	if ($self->tomcat) {

		my $tomcat_match = {
			'java.util.logging.config.file=/opt/.*tomcat.*/conf/logging.properties' => 0,
			'catalina.base=/opt/.*tomcat' => 0,
		};

		foreach my $arg (@{$self->cmdline}) {
			foreach my $match (keys %{$tomcat_match}) {
				if ($arg =~ m|$match|) {
					$tomcat_match->{$match} = 1;
				}
			}
		}

		if (sum(values %{$tomcat_match}) == scalar keys %{$tomcat_match}) {
			$self->{shared_tomcat} = 1;
		}

	}

	# ran a second time because the "only key off log files if this is shared_tomcat" only works if
	# this is ran twice. This is so things like order-manager-webapp show up as its only reference
	# is a .log file and shared_tomcat usually gets set after it sees the log file
	$self->pkg_search($rpmsave);

	bless $self, $class;

	return $self;
}

sub packages {
	return shift->{packages};
}

sub tomcat {
	return shift->{tomcat};
}

sub shared_tomcat {
	return shift->{shared_tomcat};
}

sub ports {
	return shift->tcp_ports;
}

# returns a string; yes, no, or shared

sub tomcat_string {
	my ($self) = @_;

	return "shared" if $self->{shared_tomcat};
	return ( $self->tomcat ? "yes" : "no" );
}

# returns a string; all the package names seperated by a space

sub package_name {
	my ($self) = @_;

	return "sharedtomcat" if $self->shared_tomcat;

	my $name;
	my $pkgs = $self->packages;

	if (0 != scalar @{$pkgs}) {
		$name = join " ", @{$pkgs};
	} else {
		$name = "unknown";
	}

	return $name;
}

# wait_until_stopped override

sub wait_until_stopped {
	my ($self, $timeout) = @_;

	my $pkg = $self->package_name;

	return $self->SUPER::wait_until_stopped($timeout, $pkg);
}

# returns void; a method to shut down the given process

sub shutdown {
	my ($self, $timeout) = @_;

	my $i;
	my $died;

	my $pid = $self->pid;
	my $pkg = $self->package_name;

	kill 15, $self->pid;
	print "Sent $pkg (pid $pid) a TERM signal, waiting for it to stop...\n";

	# wait for it to stop
	$died = $self->wait_until_stopped($timeout);

	# if still not dead, send it a kill signal
	if (0 == $died) {
		print "$pkg (pid $pid) not stopped, sending it a KILL signal...\n";
		kill 9, $pid;

		$died = $self->wait_until_stopped($timeout);

		# if still not dead... there are bigger problems to deal with
		if (0 == $died) {
			print "$pkg (pid $pid) is still runing even after a kill... reboot maybe?\n";
			exit;
		}
	}

	print "$pkg (pid $pid) is down!\n";

}

# returns a string; the part of the given path that is likely to belong to a package
# returns nothing when not likely part of a package at all

sub likely_pkg_file {
	my ($self, $file) = @_;

	# deleted file? remove that note
	$file =~ s/ \(deleted\)//;

	# skip stuff we don't need to look up
	return if $file =~ m|^/dev/|;
	return if $file =~ m|^/tmp/|;
	return if $file =~ m|/jdk|;
	return if $file =~ m|/jre|;
	return if $file =~ m|\.jks$|;
	return if $file =~ m|^socket|;
	return if $file =~ m|^pipe|;
	return if $file =~ m|^/var/|; # java stuff isn't usually in /var
	return if $file =~ m|^/etc/|; # or /etc
	return if $file =~ m|^/opt/apache2|; # and things with /opt/apache2 aren't java
	return if $file =~ m| |; # no spaces in the filename

	# fix cases of // (probably due to bad symlink name) to be /
	$file =~ s|//|/|g;

	# find the directory in /opt for these kinds of files
	# since they're often not part of the package, but are in
	# some subdirectory that is part of the package
	my @search = (
		'WEB-INF',
		'out$',
		'\.properties$',
		'\.data$',
		'access_log',
		'error_log',
		'apache',
		'tomcat',
		'catalina',
		'/temp',
		'\.war$',
		'\.jar$',
		'delete_me',
		'notesService',
	);

	# only key off log files if this is shared_tomcat
	if ($self->{shared_tomcat} and $file =~ m|^(/opt/.*?)/.*\.log$|) {
		$file = $1;
		return $file;
	} elsif ($file =~ m|^(/opt/.*?)/.*\.log$|) {
		return;
	}

	# remove prefix if necessary
	$file =~ s|^file://||;

	# find the basedir above /opt/ in which this file belongs
	foreach my $regex (@search) {
		if ($file =~ m|^(/opt/.*?)/.*$regex|) {
			$file = $1;
			last;
		}
	}

	return $file;
}

# returns an array ref; a list of files related to a java process that are likely to be a part of an RPM

sub likely_pkg_files {
	my ($self) = @_;

	my $pkg_checks = [];
	my $file;

	# look at args to see if things behind the = exist, and if so, what package they belong to
	foreach my $arg (@{$self->cmdline}) {
		my ($x, $val) = split /=/, $arg, 2;

		next if $x and $x =~ /Size/; # skip xSize=blah stuff

		if (defined $val and $file = $self->likely_pkg_file($val)) {
			push_if_not_in($file, $pkg_checks);
		}

		if (defined $arg and $arg =~ m|^/| and $file = $self->likely_pkg_file($arg)) {
			push_if_not_in($file, $pkg_checks);
		}

	}

	# look at open file descriptors to see what packages they are owned by
	foreach my $fd (@{$self->fds}) {
		if (defined $fd and $file = $self->likely_pkg_file($fd)) {
			push_if_not_in($file, $pkg_checks);
		}
	}

	return $pkg_checks;
}

# returns an array of two elements; 0 => true/false for tomcat, and 1 => a hash ref of which the keys are RPM packages found

sub pkg_search {
	my ($self, $cache) = @_;

	# walk through the incoming array
	foreach my $file (@{$self->likely_pkg_files}) {
		my @rpms = find_package($file, $cache);

		foreach my $rpm (@rpms) {

			next unless defined $rpm;

			# list tomcat implicitly if needed
			if ($rpm =~ /tomcat/) {
				$self->{tomcat} = 1;
				next;
			}

			push_if_not_in($rpm, $self->{packages});
		}
	}
}

# returns a string; the package name that the given file belongs to
# return undef when the given file doesn't belong to any package

sub find_package {
	my ($file, $cache) = @_;

	return $cache->cached($file) if defined $cache->cached($file);

	if (-f $file or -d $file) {
		chomp(my $rpms = `rpm -qf --qf '%{name}:%{release}\n' $file`);

		unless ($rpms =~ /is not owned by any package/) {

			my @rpm_list = split /\n/, $rpms;

			foreach my $rpm (@rpm_list) {
				my ($name, $release) = split /:/, $rpm;

				$cache->cache($file, $name) if $release;
			}
		}
	}

	$cache->cache($file, "") unless $cache->cached($file);

	return $cache->cached($file);
}

1;

