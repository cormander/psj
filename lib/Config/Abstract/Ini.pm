package Config::Abstract::Ini;

use strict;
use warnings;

use base 'Config::Abstract';

our $VERSION = '0.16';

##################################################
#%name: _parse_settings_file
#%syntax: _parse_settings_file(<@settings>)
#%summary: Reads the projects to keep track of
#%returns: a hash of $projectkey:$projectlabel

sub _parse_settings_file{
	my %result = ();
	my ($entry,$subentry) = ('',undef);
	chomp(@_);
	foreach(@_){
		# Get rid of starting/ending whitespace
		s/^\s*(.*?)\s*$/$1/;
		
		#Delete comments
		($_) = split(/[#]/,$_);
		#Skip if there's no data
		next if((! defined($_)) || $_ eq '');
		/^\s*(.*?)\s*=\s*(['"]|)(.*)\2\s*/ && do {	
			my($key,$val) = ($1,$3);
			next if($key eq '' || $val eq '');
			if(! defined($subentry) || $subentry =~ /^\s*$/){
				${$result{$entry}}{$key} = $val;
			}else{
				${$result{$entry}}{$subentry}{$key} = $val;
			}
			next;
		};
		# Select a new entry if this is such a line
		/\[(.*?)\]/ && do{
			
			$_ = $1;
			($entry,$subentry) = split('::');
			if(! defined($subentry) || $subentry =~ /^\s*$/){
				$result{$entry} = {};
			}elsif($result{$entry}){
				$result{$entry}{$subentry} = {};
			}
			next;
		};
	}
	return(\%result);
}

# We provide a DESTROY method so that the autoloader
# doesn't bother trying to find it.
sub DESTROY { }

# Autoload methods go after =cut, and are processed by the autosplit program.

1;

