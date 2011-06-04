
package Java::RPM;

sub new {
	my ($class, $pkg) = @_;

	my $self = {
		pkg => $pkg,
	};

	bless $self, $class;

	# if "sharedtomcat", set some internal defaults, and don't query RPM db
	if ("sharedtomcat" eq $pkg) {
		$self->set_sharedtomcat;

		return $self;
	}

	chomp (my $rpm = `rpm -q --qf='%{name}\n' $pkg`);

	if (0 != $?) {
		die "Can not create Java::RPM class: $rpm";
	}

	die "Internal error! pkg \"$pkg\" and rpm \"$rpm\" do not match" unless $pkg eq $rpm;

	$self->init;

	return $self;
}

# find out everything we need to know about this object

sub init {
	my ($self) = @_;

	$self->find_script("startup");
	$self->find_script("shutdown");
}

# tells this object that it's a part of sharedtomcat

sub set_sharedtomcat {
	my ($self) = @_;

	$self->{basedir} = "/opt/";
	$self->{startup} = "/opt/sharedtomcat.sh start";
	$self->{shutdown} = "/opt/sharedtomcat.sh stop";

	$self->{sharedtomcat} = 1;
}

# return whether or not this object is a part of sharedtomcat

sub sharedtomcat {
	return shift->{sharedtomcat};
}

# return the "basedir" of this object

sub basedir {
	my ($self) = @_;

	return $self->{basedir} if $self->{basedir};

	$self->find_basedir;

	return $self->{basedir};
}

# figure out what the basedir is

sub find_basedir {
	my ($self) = @_;

	chomp (my $dir = `rpm -qi $self->{pkg} | grep Relocations | awk '{print \$5}'`);

	# if it's a bad relocations... do a -ql on the RPM to try harder
	if (!-d $dir) {
		chomp ($dir = `rpm -ql $self->{pkg} | head -n1`);

		if (!-d $dir) {
			die "Unable to determine basedir for $self->{pkg}";
		}
	}

	$self->{basedir} = $dir;
}

# logic to find the shutdown and startup script of an application

sub find_script {
	my ($self, $find) = @_;

	my $script;
	my $cmd;

	return $self->{$find} if $self->{$find};

	if ("startup" eq $find) {
		$cmd = "start";
	}
	elsif ("shutdown" eq $find) {
		$cmd = "stop";
	}
	else {
		die "$find is not a valid script to look for";
	}

	my $dir = $self->basedir;

	my @wars = glob $dir . "/*.war";

	my @starts = glob $dir . "/*start*";
	my @stops = glob $dir . "/*stop*";
	my @shuts = glob $dir . "/*shutdown*";

	# set JAVA_HOME if we need to
	if (!$ENV{JAVA_HOME}) {
		if (-d "/opt/jre") {
			$ENV{JAVA_HOME} = "/opt/jre";
		}
		elsif (-d "/opt/jdk") {
			 $ENV{JAVA_HOME} = "/opt/jdk";
		}
	}

	if (-f $dir . "/conf/server.xml") {
		if (-x $dir . "/$find.sh") {
			$script = $dir . "/$find.sh";
		}
		elsif (-x $dir . "/tomcat") {
			$script = $dir . "/tomcat $cmd";
		}
	}
	elsif (0 < scalar @wars) {
		$self->set_sharedtomcat;
		return $self->find_script($find);
	}
	elsif ("start" eq $cmd and 1 == scalar @starts) {
		$script = $starts[0];
	}
	elsif ("stop" eq $cmd and 1 == scalar @stops) {
		$script = $stops[0];
	}
	elsif ("stop" eq $cmd and 1 == scalar @shuts) {
		$script = $shuts[0];
	}
	else {
		die "Could not find $find script for $self->{pkg}";
	}

	$self->{$find} = $script;

	return $script;
}

1;

