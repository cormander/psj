package Config::Abstract;

use strict;
use warnings;

our $VERSION = '0.16';

#
# ------------------------------------------------------------------------------------------------------- structural methods -----
#

sub new {
    my($class,$initialiser) = @_;
    my $self = {
		_settings => undef,
		_settingsfile => undef
	};
    bless $self,ref $class || $class;
    $self->init($initialiser);
    return $self;
}

sub init {
	my($self,$settingsfile) = @_;
	return unless(defined($settingsfile));	
	return if($settingsfile eq '');
	$self->{_settings} = $self->_read_settings($settingsfile);
	$self->{_settingsfile} = $settingsfile;
}


#
# --------------------------------------------------------------------------------------------------------- accessor methods -----
#

sub get_all_settings {
	my($self) = @_;
	# Make sure we don't crash and burn trying to return a hash from an undef reference
	return undef unless(defined($self->{_settings}));
	# Return the settings as a hash in array contect and a hash reference in scalar context
	if(wantarray){
		return %{$self->{_settings}};
	}else{
		return $self->{_settings};
	}
}

sub get_entry {
	my($self,$entryname) = @_;
	my $val;
	if($entryname =~ m|//|){
		# Getting an entry by path
		my $unpathed = $self->_unpath($entryname);
		eval("\$val = \"\${ \$self->{_settings} }$unpathed\";");
#		print("\$val = '\${ \$self->{_settings} }$unpathed ';\n");#DEBUG!!!
#		print("\$val: $val\n");#DEBUG!!!
	}else{
		$val = ${$self->{_settings}}{$entryname};
	}
	if(defined($val)){
		if(wantarray && ref($val) eq 'HASH'){
#			print STDERR ("Returning HASH in $self" . "->get_entry($entryname)\n");#DEBUG!!!
			return(%{$val});
		}else{
#			print STDERR ("Returning ref in $self" . "->get_entry($entryname)\n");#DEBUG!!!
			return($val);
		}
	}else{
		return (wantarray ? () : undef);
	}
}

sub get_entry_setting {
	my($self,$entryname,$settingname,$default) = @_;
	# Return undef if the requested entry doesn't exist
	my %entry = ();
	return(undef) unless(%entry = $self->get_entry($entryname));
	if(defined($entry{$settingname})){
		return $entry{$settingname};
	}else{
		return $default;
	}
}

sub get {
	my($self,$section,$key,$default) = @_;
	# If everything up to the key is given, get a specific key
	return $self->get_entry_setting($section,$key,$default) if(defined($key));
	# If section is given, but not key, get a specific section
	return $self->get_entry($section) if(defined($section));
	# If no parameter is given, return the entire hash
	return $self->get_all_settings();
}

#
# ---------------------------------------------------------------------------------------------------------- mutator methods -----
#

sub set_all_settings {
	my($self,%allsettings) = @_;
	return %{$self->{_settings}} = %allsettings;
}

sub set_entry {
	my($self,$entryname,$entry) = @_;
	my $unpathed = $self->_unpath($entryname);
	my $val;
	eval('${$self->{_settings}}' . $unpathed . ' = $entry;');
	return $self->get_entry($entryname) ;
}

sub set_entry_setting {
	my($self,$entryname,$settingname,$setting) = @_;
	return (${${$self->{_settings}}{$entryname}}{$settingname} = $setting);
}

sub set {
	my($self,$section,$key,$value) = @_;
	# If everything up to the key is given, set a specific key
	return $self->set_entry_setting($section,$key,$value) if(defined($value));
	# If section is given, but not key, set a specific section
	return $self->set_entry($section,$key) if(defined($key));
	# If no parameter is given, return the entire hash
	return $self->set_all_settings(%{$section});
}

sub exists {
	my($self,$section,$key) = @_;
	return defined($self->{$section}) unless (defined($key));
	return defined($self->{$section}{$key});
}

sub get_entry_names {
	my($self) = @_;
	return sort(keys(%{$self->{_settings}}));
}

#
# ------------------------------------------------------------------------------------------------------- arithmetic methods -----
#

##################################################
#%name: diff
#%syntax: diff($other_config_object)
#%summary: Generates an object with overrides for entries that can be used to patch $self into $other_config_object
#%returns: a Config::Abstract object
#%NB: This method is nowhere near working atm /EWT
sub diff {
	my($self,$diff) = @_;
	my %self_pathed = $self->_pathalise_object( '',$self->{_settings} );
	my %diff_pathed = $self->_pathalise_object( '',$diff->{_settings} );
	my $result = $self->new();
	while( my($k,$v) = each(%diff_pathed) ) {
		next if( defined($self_pathed{$k}) && $self_pathed{$k} eq $v);
		$result->set($k,$v);
	}
	return $result;
}


##################################################
#%name: patch
#%syntax: patch($patch_from_other_config_object)
#%summary: Overrides all settings that are found in the $patch object with the $patch values
#%returns: Nothing
sub patch {
	my($self,$patch) = @_;
	my %patch_pathed = $self->_pathalise_object( '',$patch->{_settings} );
	while( my($k,$v) = each(%patch_pathed) ) {
		$self->set($k,$v);
	}	
}



sub _unpath {
	my($self,$path) = @_;
	$path =~ s|^/+|{'|;
	$path =~ s|/+|'}{'|g;
	$path .= '\'}';
	return $path;
}
##################################################
#%name: _pathalise_object
#%syntax: _dumpobject(<$objectcaption>,<$objectref>,[<@parentobjectcaptions>])
#%summary: Recursively generates a string representation of the object referenced
#          by $objectref
#%returns: a string representation of the object

sub _pathalise_object{
	my($self,$name,$obj,@parents) = @_;
	my @result = ();
	if(ref($obj) eq 'HASH'){
		unless($name eq '' ){
			push(@parents,$name);
		}
		while(my($key,$val) = each(%{$obj})){
			push(@result,$self->_pathalise_object($key,$val,@parents));
		}
	}elsif(ref($obj) eq 'SCALAR'){
		push(@result,'//' . join('//',@parents) . "//$name",${$obj});
	}elsif(ref($obj) eq 'ARRAY'){
		push(@parents,$name);
		for(my $i = 0;scalar(@{$obj});$i++){
			push(@result,$self->_pathalise_object($i,${$obj}[$i],@parents));
		}
	}else{
		push(@result,'//' . join('//',@parents) . "//$name",$obj);
	}
	return @result;
}
#
# ------------------------------------------------------------------------------------------------ (de)serialisation methods -----
#

##################################################
#%name: _read_settings
#%syntax: _read_settings(<$settingsfilename>)
#%summary: Reads the key-values to keep track of
#%returns: a reference to a hash of $key:$value

sub _read_settings{
	my ($self,$settingdata) = @_;
	my @conflines;
	if(ref($settingdata) eq 'ARRAY'){
		@conflines = @{$settingdata};
	}else{
		my $settingsfile = $settingdata;
		# Read in the ini file we want to use
		# Probably not a good idea to die on error at this
		# point, but that's what we've got for the moment
		open(SETTINGS,$settingsfile) || die("Failed to open ini file ($settingsfile) for reading\n");
		@conflines = <SETTINGS>;
		close(SETTINGS);
	}
	my $settings = $self->_parse_settings_file(@conflines);
	return($settings);
}

##################################################
#%name: _parse_settings_file
#%syntax: _parse_settings_file(<@settings>)
#%summary: Reads the key-values into a hash
#%returns: a reference to a hash of $key:$value

sub _parse_settings_file{
	my $settings = {};
	eval(join('',@_));
	return($settings);
}

#
# ---------------------------------------------------------------------------------------------------------- utility methods -----
#


sub expand_tilde {
	defined($ENV{'HOME'}) && do {
		$_[0] =~ s/^~/$ENV{'HOME'}/;
	};
	return $_[0];
}


# We provide a DESTROY method so that the autoloader
# doesn't bother trying to find it.
sub DESTROY { 
	print STDERR ("Destroying Config::Abstract\n"); #DEBUG!!!
}

1;

