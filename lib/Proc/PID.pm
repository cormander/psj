
#
# Custom class to stat info about linux processes
#

package Proc::PID;

use strict;
use warnings;

use POSIX qw(ceil sysconf _SC_CLK_TCK);

use PSJ::Common;

# constructor

sub new {
	my ($class, $pid, $portsave) = @_;

	die "$pid is not an integer!" unless $pid =~ /^[0-9]+$/; 
	die "Unable to stat info for PID $pid in /proc directory" unless -d "/proc/$pid";

	my $self = {
		pid => $pid,
		portsave => $portsave,
	};

	bless $self, $class;

	$self->init;

	return $self;
}

# init all of this PID's info

sub init {
	my ($self) = @_;

	$self->{fds} = $self->_fds;
	$self->{exe} = $self->_exe;
	$self->{start_time} = $self->_start_time;
	$self->{user} = $self->_user;
	$self->{threads} = $self->_threads;
	$self->{rss_mem} = $self->_rss_mem;
	$self->{tcp_ports} = $self->_tcp_ports;
	$self->{cmdline} = $self->_cmdline;
	$self->{environ} = $self->_environ;

}

# aliases for $self->{VAR}

sub pid { return shift->{pid} }
sub fds { return shift->{fds} }
sub exe { return shift->{exe} }
sub start_time { return shift->{start_time} }
sub user { return shift->{user} }
sub threads { return shift->{threads} }
sub rss_mem { return shift->{rss_mem} }
sub tcp_ports { return shift->{tcp_ports} }
sub cmdline { return shift->{cmdline} }
sub environ { return shift->{environ} }

# returns an array ref; each element points to a file the given process has open

sub _fds {
	my $pid = shift->pid;

	return [ map { readlink "/proc/$pid/fd/$_" } dir_read("/proc/$pid/fd/") ];
}

# returns a string; the path to the binary for this process

sub _exe {
	my $pid = shift->pid;

	return readlink "/proc/$pid/exe";
}

# returns an int; the epoch timestamp of when the process started

sub _start_time {
	my $pid = shift->pid;

	# this code is crazy; I had to RTFM on the steps to do these calculations

	# number of "tickets per second" on this system
	my $tickspersec = sysconf(_SC_CLK_TCK);

	# calculate the "number of seconds since boot"
	my ($secs_since_boot) = split /\./, file_read("/proc/uptime");
	$secs_since_boot *= $tickspersec;

	# the 22nd item in /proc/#/stat is the start_time
	my $start_time = (split / /, file_read("/proc/$pid/stat"))[21];

	# calculate the epoch timestamp that this all ends up as; not sure why this is
	# subtrated from the current epoch timestamp to get an epoch timestamp, but
	# that is how it comes out...
  	return ceil(time() - (($secs_since_boot - $start_time) / $tickspersec));
}

# returns a string; the name of the user that owns this process

sub _user {
	my $pid = shift->pid;

	my $user = getpwuid((stat("/proc/$pid/"))[4]);

	return $user;
}

# returns an integer; the number of threads this process has

sub _threads {
	my $pid = shift->pid;

	return scalar dir_read("/proc/$pid/task"),
}

# returns a float; the number of MB this process is using in memory

sub _rss_mem {
	my $pid = shift->pid;

	my @output = split /\n/, file_read("/proc/$pid/status");

	foreach my $out (@output) {
		if ($out =~ /^VmRSS.*?([0-9]+) kB/) {
			return ceil($1 / 1024);
		}
	}

	return 0;
}

# returns an array ref; a list of open tcp ports the given $pid is listening on

sub _tcp_ports {
	my ($self) = @_;

	my $pid = $self->pid;

	return $self->{portsave} if $self->{portsave};

	my $lsof = find_in_path("lsof");

	return [] unless -x $lsof;

	my @arr;
	my @output = split /\n/, `$lsof -nlP -p $pid -a -i tcp`;

	foreach my $out (@output) {
		chomp $out;
		if ($out =~ /:([0-9]+) \(LISTEN\)/) {
			my $port = $1;
			push @arr, $port if $port and $port =~ /^[0-9]+$/;
		}
	}

	return [ sort {$a <=> $b} @arr ];
}


# returns an array ref; some files in /proc are seperated by NULL

sub _nattr {
	my ($self, $file) = @_;

	return [ split /\0/, file_read("/proc/" . $self->pid . "/$file") ];
}

# aliases for nattr

sub _cmdline { return shift->_nattr('cmdline') }

sub _environ { return shell2env(shift->_nattr('environ')) }

#
# external functions
#

# wait for a given PID to stop; return as soon as it stops or after the given timeout
# returns 1 if the process stopped, 0 otherwise

sub wait_until_stopped {
	my ($self, $timeout, $app_name) = @_;

	my $pid = $self->pid;
	my $died = 0;

	if ($app_name) {
		print "Waiting for $app_name (pid $pid) to stop.\n";
	} else {
		print "Waiting for pid $pid to stop.\n";
	}

	for (my $i = 1; $i <= $timeout; $i++) {

		# stat info for this $pid
		eval "Proc::PID->new($pid)";

		# if the above eval threw an exception, then the PID doesn't exist
		# it seems odd that we're waiting for an exception to happen in order to continue,
		# but I really couldn't think of a better way to do this
		if ($@) {
			$died = 1;
			# I could just use "last" here instead; but NAH!
			$i = $timeout+1;
		} else {
			# if we have the optional $app_name, use it in the output
			if ($app_name) {
				print "Waiting for $app_name (pid $pid) to stop ($i of $timeout)...\n";
			} else {
				print "Waiting for pid $pid to stop ($i of $timeout)...\n";
			}
			sleep 1;
		}
	}

	if ($died) {
		print "PID $pid is down!\n";
	} else {
		print "PID $pid did not stop!\n" ;
	}

	return $died;
}

1;

