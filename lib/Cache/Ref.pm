
#
# A custom helper class for caching info in hash references and fetching the values
# without having to worry about uninitialized value warnings from perl
#

package Cache::Ref;

use strict;
use warnings;

# constructor

sub new {
	my ($class) = @_;

	my $self = {};

	bless $self, $class;

	return $self;
}

# returns nothing; caches key => val in given cache

sub cache {
	my ($self, $key, $val) = @_;

	return unless $key;

	if ($self->cached($key) and "ARRAY" eq ref $self->{$key}) {
		push @{$self->{$key}}, $val;
	}
	elsif ($self->cached($key)) {
		my $tmp = $self->{$key};
		$self->{$key} = [ $tmp, $val ];
	}

	$self->{$key} = $val unless $self->cached($key);
}

# returns the cached value for $key if it exists

sub cached {
	my ($self, $key) = @_;

	my $val;

	return undef unless $key;

	if (defined $self->{$key} and $self->{$key} eq "") {
		return "";
	}

	if (defined $self->{$key}) {
		if ("ARRAY" eq ref $self->{$key}) {
			return ( wantarray ? @{$self->{$key}} : $self->{$key}[-1] );
		} else {
			return ( wantarray ? ($self->{$key}) : $self->{$key} );
		}
	}

	return undef;
}

1;

