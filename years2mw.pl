#!/usr/bin/perl -w

# This is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This file is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this file; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

use MediaWiki::Bot;
use YAML::Tiny;
use Getopt::Long;
use Pod::Usage;
use encoding 'utf8';
use strict;

my $text = '{{1800-tallet}}
{{År-side}}';

my ($config, $from, $to, $verbose, $debug) = get_options();

# Check that from is bigger than or equal to to
if ($to < $from) { die "First year must be smaller than or equal to last year!\n"; }

# Open the config
my $yaml = YAML::Tiny->new;
if (-e $config) {
	$yaml = YAML::Tiny->read($config);
} else {
	die "Could not find $config\n";
}

# Set up a Mediawiki bot 
my $bot = MediaWiki::Bot->new({
	assert      => 'bot',
}) or die "Could not create bot";

# Choose the wiki
if ($debug) { 
    print "Wiki: ", $yaml->[0]->{wikihost};
    if ($yaml->[0]->{wikipath}) {
      print " / ", $yaml->[0]->{wikipath}; 
    }
    print "\n";
}
$bot->set_wiki({
	host        => $yaml->[0]->{wikihost},
	path        => '', # FIXME $yaml->[0]->{wikipath},
}) or die "Could not set wiki";

# Log in to the wiki
if ($debug) { print "Wiki user: ", $yaml->[0]->{wikiuser}, ":", $yaml->[0]->{wikipass}, "\n"; }
# Make sure we are logged out first
$bot->logout();
my $login = $bot->login({
	username => $yaml->[0]->{wikiuser},
	password => $yaml->[0]->{wikipass},
}) or die "Login failed ", $bot->{'error'}->{'code'}, " ", $bot->{'error'}->{'details'};
if ($debug) { print "\t Login: $login\n"; }

for (my $i = $from; $i <= $to; $i++) {

	if ($verbose) { print "$i "; }

    # Output
	$bot->edit({
		page      => $i,
		text      => $text,
		summary   => $yaml->[0]->{wikimsg},
		assertion => 'bot', 
	}) or die "Edit failed: ", $bot->{'error'}->{'code'}, " ", $bot->{'error'}->{'details'};
	
}

if ($verbose) { print "\n"; }

### SUBROUTINES

# Get commandline options
sub get_options {
  my $config    = '';
  my $from      = '';
  my $to        = '';
  my $verbose   = '';
  my $debug     = '';
  my $help      = '';

  GetOptions("c|config=s"   => \$config,
             "f|from=s"     => \$from, 
             "t|to=s"       => \$to, 
             "v|verbose"    => \$verbose,
             "d|debug"      => \$debug,
             "h|help"       => \$help,
             );
  
  pod2usage(-exitval => 0) if $help;
  pod2usage( -msg => "\nMissing Argument: -c, --config required\n", -exitval => 1) if !$config;
  pod2usage( -msg => "\nMissing Argument: -f, --from required\n", -exitval => 1) if !$from;
  pod2usage( -msg => "\nMissing Argument: -t, --to required\n", -exitval => 1) if !$to;

  return ($config, $from, $to, $verbose, $debug);
}       

__END__

=head1 NAME
    
year2mw.pl - Create a series of pages for years, all with the same text
        
=head1 SYNOPSIS
            
csv2mw.pl -c myconfig.yaml -f 1900 -t 1950

=head1 OPTIONS
              
=over 8

=item B<-c, --config>

Path to a config file in YAML format. First line is assumed to be variable names. 

=item B<-f, --from>

First year in series.  

=item B<-t, --to>

Last year. 

=item B<-v, --verbose>

Turn on verbose output. 

=item B<-d, --debug>

Turn on debug output. 

=item B<-h, --help>

Print this documentation. 

=back
                                                               
=cut
