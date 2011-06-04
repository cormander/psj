package PSJ::Common;

use strict;
use warnings;

use POSIX qw(ttyname floor);
use Carp;

use base 'Exporter';

our @EXPORT = qw( file_read file_write dir_read mkdir_p find_in_path pidof java_version_from_exe in_array push_if_not_in shell2env who_is_running_this epoch2runtime sum trim );

# returns the entire content of a file as a string

sub file_read {
	my ($file) = @_;

	open my $fh, $file or croak "Unable to open $file; $!";
	local $/;
	my $content = <$fh>;
	close $fh;

	return $content;
}

# returns nothing; writes the given content to a file

sub file_write {
	my ($file, $content) = @_;

	open my $fh, ">" . $file or croak "Unable to open $file; $!";
	print {$fh} $content;
	close $fh;
}

# returns an array; each is a different element of the directory, omitting . and ..

sub dir_read {
	my ($dir) = @_;

	my @content;

	opendir my $dh, $dir or croak "Unable to open $dir; $!";
	while (my $elem = readdir $dh) {
		next if $elem eq ".";
		next if $elem eq "..";
		push @content, $elem;
	}
	close $dh;

	return @content;
}

# returns nothing; run mkdir -p

sub mkdir_p {
	my ($dir) = @_;

	`mkdir -p $dir`;
}

# returns a string; the full path to the given file as searched for in ENV

sub find_in_path {
	my ($file) = @_;

	my @path = split /:/, $ENV{PATH} . ":/sbin:/usr/sbin:/usr/local/sbin";

	foreach my $dir (@path) {
		my $str = $dir . '/' . $file;

		return $str if -f $str;
	}

	return "";
}

# returns an array; pids of the given process name

sub pidof {
	my ($prog) = @_;

	my $tr = find_in_path("tr");
	my $pidof = find_in_path("pidof");

	croak "Could not find tr command in PATH" unless -x $tr;
	croak "Could not find pidof command in PATH" unless -x $pidof;

	return split / /, `$pidof $prog | $tr '\n' ' '`;
}

# returns a string; the java version of the given java binary

sub java_version_from_exe {
	my ($exe) = @_;

	croak "Not executable: $exe" unless -x $exe;

	my $head = find_in_path("head");

	croak "Could not find head command in PATH" unless -x $head;

	chomp(my $out = `$exe -version 2>&1 | $head -n1`);

	if ($out =~ /^java version "(.*?)"$/i) {
		return $1;
	} else {
		croak "Not a java binary: $exe";
	}
}

# returns true if $needle is found in @haystack; false otherwise

sub in_array {
	my ($needle, @haystack) = @_;

	foreach my $hay (@haystack) {
		return 1 if $hay eq $needle;
	}

	return 0;
}

# returns nothing; only push $needle onto @{$haystack} if it isn't in it already

sub push_if_not_in {
	my ($needle, $haystack) = @_;

	return unless $needle; # don't push empty strings onto the array

	croak "Second argument to push_if_not_in is not an array ref" unless "ARRAY" eq ref $haystack;

	push @{$haystack}, $needle if (!in_array($needle, @{$haystack}));
}

# returns a hash ref; converts an array of key=val values to a hash

sub shell2env {
	my ($ref) = @_;

	croak "Argument to shell2env is not an array ref" unless "ARRAY" eq ref $ref;

	my $h = {};

	foreach my $line (@{$ref}) {
		my ($key, $val) = split /=/, $line, 2;

		$h->{$key} = $val;
	}

	return $h;
}

# determine the real username of the person running this, even if ran via sudo
# in list context, return an array; the first element is the username, the second is the uid
# in scalar context, return a string; the username

sub who_is_running_this {

	my $user;
	my $uid;

	my $tty = ttyname(1);

	if ($tty and -r $tty) {
		$uid = (lstat($tty))[4];
		$user = getpwuid($uid);
	}

	if (!$user or "root" eq $user) {
		$user = $ENV{USER};
	}

	if (!$user or "root" eq $user) {

		if ($ENV{SUDO_USER} and $ENV{SUDO_USER} ne "root") {
			$user = $ENV{SUDO_USER};
		}

	}

	# ???
	if (!$user) {
		$user = "unknown";
		$uid = -1;
	}

	if (!$uid) {
		$uid = getpwnam($user);
	}

	# if still root, append the IP address
	if ("root" eq $user and -r "/proc/$$/ipaddr" ) {
		chomp(my $ipaddr = file_read("/proc/$$/ipaddr"));

		$user = "root logged in from $ipaddr" if $ipaddr;
	}

	return ( wantarray ? ( $user, $uid ) : $user );

}

# returns a string; the amount of time elapsed since the given epoch as a short string

sub epoch2runtime {
	my ($epoch) = @_;

	my $tm;
	my $nn;

	my $runtime = time() - $epoch;

	if (0 > $runtime) {
		return "???";
	}

	# longer than a day?
	if ($runtime > (60*60*24)) {
		$tm = floor($runtime / (60*60*24));
		$nn = "day";
	}
	# longer than an hour?
	elsif ($runtime > (60*60)) {
		$tm = floor($runtime / (60*60));
		$nn = "hr";
	}
	# longer than a minute?
	elsif ($runtime > 60) {
		$tm = floor($runtime / 60);
		$nn = "min";
	}
	else {
		$tm = $runtime;
		$nn = "second";
	}

	return $tm . " " . $nn . ( $tm > 1 ? "s" : "" );
}

# returns an int; adds all args together

sub sum {
       my (@nums) = @_;

       my $total = 0;

       foreach my $num (@nums) {
	       $total += $num;
       }

       return $total;
}

# returns a string; the given string with whitespace stripped from the beginning and end

sub trim {
	my ($str) = @_;

	$str =~ s/^\s+//;
	$str =~ s/\s+$//;

	return $str;
}

1;

