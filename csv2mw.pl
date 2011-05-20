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

use Text::CSV;
use MediaWiki::Bot;
use YAML::Tiny;
use Template;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use encoding 'utf8';
use strict;

my ($config, $inputfile, $template, $limit, $verbose, $debug) = get_options();

# Check that the input file exists
if (! -e $inputfile) { die "Could't find $inputfile!\n"; }

# Open the config
my $yaml = YAML::Tiny->new;
if (-e $config) {
	$yaml = YAML::Tiny->read($config);
} else {
	die "Could not find $config\n";
}

if (! -e $template) { die "Could't find $template!\n"; }
# Set up Template Toolkit
my $ttconfig = {
    INCLUDE_PATH => '.',  # or list ref
    INTERPOLATE  => 1,    # expand "$var" in plain text
    POST_CHOMP   => 0,    # cleanup whitespace 
};
my $tt2 = Template->new($ttconfig) || die Template->error(), "\n";

# Set up a Mediawiki bot 
my $bot = MediaWiki::Bot->new({
	assert      => 'bot',
}) or die "Could not create bot";

# Choose the wiki
if ($debug) { print "Wiki: ", $yaml->[0]->{wikihost}, " / ", $yaml->[0]->{wikipath}, "\n"; }
$bot->set_wiki({
	host        => $yaml->[0]->{wikihost},
	path        => '', # FIXME $yaml->[0]->{wikipath},
}) or die "Could not set wiki";

# Log in to the wiki
if ($debug) { print "Wiki user: ", $yaml->[0]->{wikiuser}, ":", $yaml->[0]->{wikipass}, "\n"; }
# Make sure we are logged out first
$bot->logout();
$bot->login({
	username => $yaml->[0]->{wikiuser},
	password => $yaml->[0]->{wikipass},
}) or die "Login failed ", $bot->{'error'}->{'code'}, " ", $bot->{'error'}->{'details'};

# Read the input file
my $csv = Text::CSV->new ( { 
  binary   => 1, 
  sep_char => ';',
} ) or die "Cannot use CSV: ".Text::CSV->error_diag ();
open my $fh, "<:encoding(utf8)", $inputfile or die "$inputfile: $!";
$csv->column_names ($csv->getline($fh));
my $records = $csv->getline_hr_all($fh);
$csv->eof or $csv->error_diag();
close $fh;

my $count = 0;
foreach my $record ( @{$records} ) {
    # Output
	my $text = '';
	$tt2->process($template, { 'rec' => $record }, \$text, binmode => ':utf8') || die $tt2->error();
	# die $text;
	# Check to see if the page we are about to edit already exists
	my $wikitext = $bot->get_text($record->{'Sidetittel'});
   	if (defined $wikitext) {
	    my ($head, $tail) = split '<!-- Do NOT edit above this line! csv2mw -->', $wikitext;
		if ($tail) { 
			$text = $text . $tail;
		}
	}
	$bot->edit({
		page    => $record->{'Sidetittel'},
		text    => $text,
		summary => $yaml->[0]->{wikimsg},
		# section => 'new',
	});
	if ($verbose) { print $record->{'Tittel'}, "\n" }
	$count++;
	# Honour the --limit option
	if ($limit && $count == $limit) {
		last;
	}
}
print "$count records\n";

### SUBROUTINES

# Get commandline options
sub get_options {
  my $config    = '';
  my $inputfile = '';
  my $template  = '';
  my $limit     = 0;
  my $verbose   = '';
  my $debug     = '';
  my $help      = '';

  GetOptions("c|config=s"   => \$config,
             "i|input=s"    => \$inputfile, 
             "t|template=s" => \$template, 
             "l|limit=i"    => \$limit,
             "v|verbose"    => \$verbose,
             "d|debug"      => \$debug,
             "h|help"       => \$help,
             );
  
  pod2usage(-exitval => 0) if $help;
  pod2usage( -msg => "\nMissing Argument: -c, --config required\n", -exitval => 1) if !$config;
  pod2usage( -msg => "\nMissing Argument: -i, --input required\n", -exitval => 1) if !$inputfile;
  pod2usage( -msg => "\nMissing Argument: -t, --template required\n", -exitval => 1) if !$template;

  return ($config, $inputfile, $template, $limit, $verbose, $debug);
}       

__END__

=head1 NAME
    
csv2mw.pl - Copy metadata from a CSV file to a MediaWiki wiki
        
=head1 SYNOPSIS
            
csv2mw.pl -c myconfig.yaml -i input.csv -t mytemplate.tt

=head1 OPTIONS
              
=over 8

=item B<-c, --config>

Path to a config file in YAML format. First line is assumed to be variable names. 

=item B<-i, --input>

Path to CSV file.  

=item B<-t, --template>

Path to Template Toolkit template. 

=item B<-l, --limit>

Max number of records to handle. 

=item B<-v, --verbose>

Turn on verbose output. 

=item B<-d, --debug>

Turn on debug output. 

=item B<-h, --help>

Print this documentation. 

=back
                                                               
=cut
