
package Java::Running;

use strict;
use warnings;

use Java::App;
use Java::RPM;
use Cache::Ref;
use PSJ::Common;
use Config::Abstract::Ini;

our $Verbose = 0;

sub new {
	my ($class) = @_;

	my $self = {
		class => $class,
		ini_file => '/etc/psj.ini',
		proc => {},     # each element is a Java::App
		ports => {},    # each element is the pid of a Java::App
		packages => {}, # each element is an array ref containing pids of Java::App
		rpmsave => new Cache::Ref,
		javaversion => new Cache::Ref,
		portsave => {},
	};

	bless $self, $class;

	$self->init_config;

	$self->init_ports;

	my @pids = pidof("java");

	foreach my $pid (@pids) {
		$self->init_java_app($pid);
	}

	return $self;
}

sub init_config {
	my ($self) = @_;

	eval {
		# parse the conf file to get all the variables needed
		my $ini = Config::Abstract::Ini->new($self->{ini_file});

		$self->{config} = $ini->get_all_settings;
	};

	# if there was a problem
	$self->debug("Unable to load $self->{ini_file}: $@") if $@;

}

#

sub get_config {
	my ($self, $action, $type, $target) = @_;

	my $t = $type . "_" . $action;

	if ($self->{config}{$target}{$t}) {
		return $self->{config}{$target}{$t};
	} elsif ($self->{config}{default}{$t}) {
		return $self->{config}{default}{$t};
	}
}

#

sub get_cmd_start {
	my ($self, $target, $noini) = @_;

	unless ($noini) {
		my $script = $self->get_config("start", "command", $target);

		return $script if $script;
	}

	return Java::RPM->new($target)->find_script("startup");

}

#

sub get_cmd_stop {
	my ($self, $target, $noini) = @_;

	unless ($noini) {
		my $script = $self->get_config("stop", "command", $target);

		return $script if $script;
	}

	return Java::RPM->new($target)->find_script("shutdown");
}

#

sub get_timeout_start {
	my ($self, $target) = @_;

	my $timeout = $self->get_config("start", "timeout", $target);

	return 10 unless $timeout;

	return $timeout;
}

#

sub get_timeout_stop {
	my ($self, $target) = @_;

	my $timeout = $self->get_config("stop", "timeout", $target);

	return 10 unless $timeout;

	return $timeout;
}

# returns void; fills $self->{portsave} with data

sub init_ports {
	my ($self) = @_;

	my $lsof = find_in_path("lsof");

	return unless -x $lsof;

	my $ref = {};
	my @output = split /\n/, `$lsof -nlP -a -i tcp`;

	foreach my $out (@output) {
		chomp $out;
		if ($out =~ /\S*?\s*?([0-9]+).*:([0-9]+) \(LISTEN\)/) {
			my $pid = $1;
			my $port = $2;
			push @{$ref->{$pid}}, $port if $pid and $port and $pid =~ /^[0-9]+$/ and $port =~ /^[0-9]+$/;
		}
	}

	# sort each port list
	foreach my $pid (keys %{$ref}) {
		$ref->{$pid} = [ sort {$a <=> $b} @{$ref->{$pid}} ];
	}

	$self->{portsave} = $ref;
#	return [ sort {$a <=> $b} @arr ];

}

# returns void; news up a Java::App and does the needed mappings

sub init_java_app {
	my ($self, $pid) = @_;

	my $java;
	my $exe;

	eval {
		$java = new Java::App($pid, $self->{rpmsave}, ( "ARRAY" eq ref $self->{portsave}{$pid} ? $self->{portsave}{$pid} : [] ));
		$exe = $java->exe;
	};

	if ($@) {
		debug($@);
		return;
	}

	unless ($exe) {
		debug("Could not stat exe for Java::App('$pid'), process died while running?");
		return;
	}

	if (!$self->{javaversion}->cached($exe)) {
		$self->{javaversion}->cache($exe, java_version_from_exe($exe));
	}

	$java->set_version($self->{javaversion}->cached($exe));

	# save port to PID mappings
	foreach my $port (@{$java->ports}) {
		$self->{ports}{$port} = $pid;
	}

	# save package to PID mappings
	foreach my $pkg (@{$java->packages}) {
		push @{$self->{packages}{$pkg}}, $pid;
	}

	# save this object
	$self->{proc}{$pid} = $java;
}

# returns an array ref; each element is a Java::App

sub get_running_apps {
	my ($self) = @_;

	my $ref = [];

	foreach my $pid (keys %{$self->{proc}}) {
		push @{$ref}, $self->{proc}{$pid};
	}

	return $ref;
}

# returns an array ref; each element is a Java::App

sub get_running_shared_tomcat {
	my ($self) = @_;

	my $ref = [];

	foreach my $java (@{$self->get_running_apps}) {
		push @{$ref}, $java if $java->shared_tomcat;
	}

	return $ref;
}

# returns an array ref; each element is a Java::App

sub get_running_apps_by_name {
	my ($self, $target) = @_;

	if ("sharedtomcat" eq $target) {
		return $self->get_running_shared_tomcat;
	}

	if ($target =~ /^[0-9]+$/) {
		return [ $self->get_running_app_by_pid($target) ];
	}

	my $ref = [];

	foreach my $pid (@{$self->{packages}{$target}}) {
		push @{$ref}, $self->{proc}{$pid};
	}

	return $ref;
}

# returns a Java::App object

sub get_running_app_by_port {
	my ($self, $port) = @_;

	return ( $self->{ports}{$port} ? $self->{ports}{$port} : undef );
}

# returns a Java::App object

sub get_running_app_by_pid {
	my ($self, $pid) = @_;

	return $self->{proc}{$pid};
}

# returns an integer; waits for $target to appear

sub wait_to_start {
	my ($self, $target, $timeout) = @_;

	my $class = $self->{class};

	my $started = 0;

	print "Waiting for $target to start.\n";

	for (my $i = 1; $i <= $timeout; $i++) {

		print "Waiting for $target to start ($i of $timeout)...\n";

		# re-init the class to re-gether info
		$self = new $class;

		my $obj = $self->get_running_apps_by_name($target);

		if (0 != scalar @{$obj}) {
			$started = 1;
			last;
		}

		sleep 1;

	}

	if ($started) {
		print "$target has started!\n";
	} else {
		print "$target did NOT start!\n" ;
	}

	return $started;
}

# debugging

sub debug {
	print join(" ", $@), "\n" if $Verbose;
}

# list running java processes

sub list {
	my ($self, $out_format) = @_;

	my $output;

	my @HEAD = ("PID","Application","Runtime","Tomcat","JAVA_HOME","User","Threads","RSS Mem","Java Version","Ports");
	my $ha = []; # holds all the output data
	my $hh = {}; # holds the column lengths for each of @HEAD

	# initialize the column lengths from @HEAD
	foreach my $h (@HEAD) {
		$hh->{$h} = length $h;
	}

	foreach my $java (@{$self->get_running_apps}) {

		my @pkgs = @{$java->packages};

		my $a = [
			sprintf("%5s", $java->pid),
			( 0 != scalar @pkgs ? [ @pkgs ] : [ "unknown" ] ),
			epoch2runtime($java->start_time),
			$java->tomcat_string,
			( $java->java_home ? $java->java_home : "(none)" ),
			$java->user,
			$java->threads,
			$java->rss_mem,
			$java->get_version,
			( scalar @{$java->ports} ? join(",", @{$java->ports}) : "(none)" ),
		];

		# it can't be any more cryptic than this, huh?
		# basically, walk along each row and identify the largest length for that column
		# and store it so when everything is displayed, everything is lined up nicely
		for (my $i = 0; $i < scalar @{$a}; $i++) {
			if ("ARRAY" eq ref $a->[$i]) {
				for (my $n = 0; $n < scalar @{$a->[$i]}; $n++) {
					$hh->{$HEAD[$i]} = (length $a->[$i][$n]) if length $a->[$i][$n] > $hh->{$HEAD[$i]};
				}
			} else {
				$hh->{$HEAD[$i]} = (length $a->[$i]) if length $a->[$i] > $hh->{$HEAD[$i]};
			}
		}

		push @{$ha}, $a;

	}

	if (!$out_format) {

		my $format = "";
		my @aformat = ("", "-", "-", "-", "-", "-", "-", "-", "-", "-");

		# this constructs the $format string, either putting a - inbetween % and s based on @aformat
		for (my $i = 0; $i < scalar @aformat; $i++) {
			$format .= "%" . $aformat[$i] . $hh->{$HEAD[$i]} . "s  ";
		}

		$format .= "\n";

		# first line of output is the definition for each column
		$output = sprintf($format, @HEAD);

		# @{$ha} is an array ref full of array refs; each of which could have more than one array ref
		# this allows for a single PID to have multiple applications displayed grouped together
		foreach my $a (@{$ha}) {

			my $apps = $a->[1];
			$a->[1] = shift @{$apps};

			$output .= sprintf($format, @{$a});

			foreach (@{$apps}) {
				$output .= sprintf($format, ( " ", $_, " ", " ", " ", " ", " ", " ", " ", " " ) );
			}
		}

		if (0 == scalar @{$ha}) {
			$output = "No Java processes are running.\n";
		}
	} elsif ("xml" eq $out_format) {
		$output = "<psj>\n";

		foreach my $a (@{$ha}) {

			$output .= "\t<process>\n";

			for (my $n = 0; $n < scalar @{$a}; $n++) {

				my $tag = lc $HEAD[$n];
				$tag =~ s/ /_/g;

				if ("ARRAY" eq ref $a->[$n]) {
					$output .= "\t\t<" . $tag . "s>\n";

					foreach my $p (@{$a->[$n]}) {
						$output .= "\t\t\t<" . $tag . ">" . $p . "</" . $tag . ">\n";
					}

					$output .= "\t\t</" . $tag . "s>\n";
				} else {
					$output .= "\t\t<" . $tag . ">" . trim($a->[$n]) . "</" . $tag . ">\n";
				}

			}

			$output .= "\t</process>\n";

		}

		$output .= "</psj>\n";
	} else {
		$output = "Unknown output format requested.\n";
	}

	#
	# TODO: get crons
	#

	print $output;

	return 0;
}

# wait for the given target to stop by itself before killing it

sub waitstop {
	my ($self, $target) = @_;

	if (!$self->is_running($target)) {
		print "$target does not appear to be running.\n";
		return 0;
	}

	my $timeout = $self->get_timeout_stop($target);

	foreach my $java (@{$self->get_running_apps_by_name($target)}) {

		my $died = $java->wait_until_stopped($timeout);

		next if $died;

		$java->shutdown($timeout);

	}

	return 0;
}

# immediately kill the given target

sub kill {
	my ($self, $target) = @_;

	if (!$self->is_running($target)) {
		print "$target does not appear to be running.\n";
		return 0;
	}

	foreach my $java (@{$self->get_running_apps_by_name($target)}) {
		$java->shutdown($self->get_timeout_stop($target));
	}

	return 0;
}

# look for a shutdown script and execute it

sub stop {
	my ($self, $target, $noini) = @_;

	if (!$self->is_running($target)) {
		print "$target does not appear to be running.\n";
		return 0;
	}

	my $script = $self->get_cmd_stop($target, $noini);

	print "Executing $script\n";
	system ($script);

	$self->waitstop($target);

	return 0;
}

# look for a startup script and execute it

sub start {
	my ($self, $target, $noini) = @_;

	# handle special case of "all"
	if ("all" eq $target) {
		return $self->start_all;
	}

	if ($self->is_running($target)) {
		print "$target is already running.\n";
		return 0;
	}

	my $script = $self->get_cmd_start($target, $noini);

	if ($self->get_config("start", "echo", $target)) {
		print "Not starting to due psj.ini configuration for $target\n\n";
		print "To start this application, please run: $script\n\n";
		return 0;
	}

	print "Executing $script\n";
	system ($script);

	return $self->waitstart($target);
}

# wrap stop and start

sub restart {
	my ($self, $target) = @_;

	$self->stop($target);

	$self = new Java::Running;

	$self->start($target);
}

# check if the given target is running

sub is_running {
	my ($self, $target) = @_;

	return scalar @{$self->get_running_apps_by_name($target)};
}

# wait for the given target to start

sub waitstart {
	my ($self, $target) = @_;

	my $ret = $self->wait_to_start($target, $self->get_timeout_start($target));

	if (1 != $ret) {
		return 1;
	}

	return 0;
}

# look for installed packages that looks like Java Applications and start them all

sub start_all {
	my ($self, $target) = @_;

	my @pkgs = split /\n/, `rpm -qa --qf='%{name}.%{release}\n' | cut -d . -f 1`;

	my @apps_to_start;
	my @do_not_start = ("fraudnetcron-consumer", "MiniRefunder", "rnowjms-consumer", "rnowjms-producer");

	my $sharedtomcat;

	foreach my $pkg (@pkgs) {

		my $rpm;

		eval {
			$rpm = new Java::RPM($pkg);

			die unless $rpm->basedir =~ m|^/opt/|;
			die if $rpm->basedir =~ m|apache|;
			die if $rpm->basedir =~ m|tomcat|;
			die if $rpm->basedir =~ m|jdk|;
			die if $rpm->basedir =~ m|jre|;
			die if $rpm->basedir =~ m|splunk|;

		};

		if ($@) {
			$self->debug($@);
			next;
		}

		# package exception list
		if (in_array($pkg, @do_not_start)) {
			print "NOT going to start $pkg!!\n";
			next;
		}

		# is this package in sharedtomcat?
		if ($rpm->sharedtomcat) {
			next if $sharedtomcat; # already starting sharedtomcat
			$sharedtomcat = 1;
			$pkg = "sharedtomcat";
		}

		push @apps_to_start, $pkg;
		print "Going to start $pkg\n";
	}

	print "\n";

	# loop through and start these apps
	foreach my $app (@apps_to_start) {
		print "Starting $app\n";
		$self->start($app);
	}

	return 0;
}

1;

