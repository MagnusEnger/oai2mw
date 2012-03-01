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

# TODO
# Check for duplicate titles
# Make it possible to harvest just a given list of sets from a repository
# Make it possible to specify the metadataformat to be harvested per repository
# Fix the "path" part of the wiki setup

use Net::OAI::Harvester;
use MediaWiki::Bot;
use YAML::Tiny;
use Template;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use strict;

my ($config, $all, $record, $yearintitle, $limit, $info, $verbose, $debug) = get_options();

# Open the config
my $yaml = YAML::Tiny->new;
if (-e $config) {
	$yaml = YAML::Tiny->read($config);
} else {
	die "Could not find $config\n";
}

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

# Loop through all the repositories in the config file
foreach my $source (@{ $yaml->[0]->{sources} }) {

	# Create a harvester
	my $harvester = Net::OAI::Harvester->new( 
	    'baseURL' => $source->{baseurl},
	);

	if ($info) {

		# If $info is set, we print some info about the repo and then exit

		# Find out the name for a repository
		my $identity = $harvester->identify();
		print "* Name: ",$identity->repositoryName(),"\n";

		# List sets
		my $sets = $harvester->listSets();
		print "\n* Sets\n";
		foreach ( $sets->setSpecs() ) { 
			print "set spec: $_ ; set name: ", $sets->setName( $_ ), "\n";
		}

		# List metadataformats
		print "\n* Metadata formats: ";
		my $list = $harvester->listMetadataFormats();
		print join( ',', $list->prefixes() ),"\n\n";

	  exit;

	}

	if ($all) {

		# List all the records in the repository
		my $records = $harvester->listAllRecords( 
			  'metadataPrefix'    => 'oai_dc' 
		);
		my $count = 0;
		while ( my $record = $records->next() ) {
			my $header = $record->header();
			my $metadata = $record->metadata();
			if ($metadata->title()) {
				print $header->identifier(), ": ", $metadata->title(), "\n";
				$count++;
			}
	    # Honour the --limit option
			if ($count == $limit) {
				last;
			}
		}
		print "$count records\n";

		exit;

	}

	if ($record) {

		# Get info about 1 record
		my $rec = $harvester->getRecord( 
		'identifier'     => $record,
		'metadataPrefix' => 'oai_dc',
		);

		# Dump the Net::OAI::Record::Header object
		# my $header = $rec->header();
		# print Dumper $header;

		# Dump the metadata object 
		my $metadata = $rec->metadata();
		print Dumper $metadata;

		exit;

	}

	# Walk through all the records in the repository, respecting --limit
	my $records = $harvester->listAllRecords( 
		  'metadataPrefix'    => 'oai_dc' 
	);
	my $count = 0;
	my %titles;
	while ( my $record = $records->next() ) {
		my $header = $record->header();
		my $metadata = $record->metadata();
		# We only care about records that have a title
		if ($metadata->title()) {
			my %record = metadata2structure($metadata);
			# Check to see if we have already seen a record with this title
			$titles{$record{'title'}}++;
			if ($titles{$record{'title'}} > 1) {
			    # If this was seen before, add the number to the title
			    $record{'title'} = $record{'title'} . ' (' . $record{'number'} . ')';
			    if ($verbose) { print "Oops, seen before! ", $record{'title'}, "\n" }
			}
			# Output
			my $text = '';
			print Dumper %record if $debug;
			$tt2->process('mwtemplate.tt', { 'rec' => \%record }, \$text) || die $tt2->error();
			# Check to see if the page we are about to edit already exists
			my $wikitext = $bot->get_text($metadata->title());
			if (defined $wikitext) {
				my ($head, $tail) = split '<!-- Do NOT edit above this line! oai2mw -->', $wikitext;
				if ($tail) { 
					$text = $text . $tail;
				}
			}
			my $title = $record{'title'};
			if ( $yearintitle && $record{'year'} && $record{'year'} ne '' ) {
			  $title = "$title ($record{'year'})";
			}
			$bot->edit({
				page    => $title,
				text    => $text,
				summary => $yaml->[0]->{wikimsg},
				# section => 'new',
			});
			if ($verbose) { print $metadata->identifier(), ': ', $metadata->title(), "\n" }
			$count++;
		}
		# Honour the --limit option
		if ($limit && $count == $limit) {
			last;
		}
	}
	print "$count records\n";

}

### SUBROUTINES

sub metadata2structure {

	my $meta = shift;
	my %data;

	# Misc data
	$data{'title'}        = $meta->title();
	$data{'publisher'}    = $meta->publisher();
	$data{'language'}     = $meta->language();
	$data{'description'}  = $meta->description();
	$data{'relation'}     = $meta->relation();
	# TODO Make the word used for "Kategori" configurable
	$data{'relation_cat'} = '[[Kategori:' . ucfirst($meta->relation()) . ']] ';

  # Date (year)
  my @dates = $meta->date();
  foreach my $date (@dates) {
    if (length($date) == 4) {
      $data{'year'} = $date;
    }
  }

	# Identifier
	my $identifier    = $meta->identifier();
	$identifier =~ m/.*\/([0-9]{1,9})$/;
	$data{'number'} = $1;

	# Coverage
	my @coverage = $meta->coverage();
	foreach my $cover (@coverage) {
		# Skip anything that starts with a number
		if ($cover =~ m/^([^0-9].*)$/i) {
			next if (substr($1, 0, 3) eq 'UTM');
			next if ($1 eq '' || $1 eq ' ' || $1 eq 'Telemark');
			$data{'coverage'} .= $1 . ", ";
			$data{'coverage_cat'} .= '[[Kategori:' . ucfirst($1) . ']] ';
		}
	}

	# Subjects
	my @subjects = $meta->subject();
	foreach my $subject (@subjects) {
		next if ($subject eq '' || $subject eq ' ');
		$data{'subjects'} .= $subject . ", ";
		$data{'subjects_cat'} .= '[[Kategori:' . ucfirst($subject) . ']] ';
	}

	return %data;

}

# Get commandline options
sub get_options {
  my $config      = '';
  my $all         = '';
  my $record      = '';
  my $yearintitle = '';
  my $limit       = 0;
  my $info        = '';
  my $verbose     = '';
  my $debug       = '';
  my $help        = '';

  GetOptions("c|config=s"    => \$config,
             "a|all"         => \$all, 
             "r|record=s"    => \$record, 
             "y|yearintitle" => \$yearintitle, 
             "l|limit=i"     => \$limit,
             "i|info"        => \$info,
             "v|verbose"     => \$verbose,
             "d|debug"       => \$debug,
             "h|help"        => \$help,
             );
  
  pod2usage(-exitval => 0) if $help;
  pod2usage( -msg => "\nMissing Argument: -c, --config required\n", -exitval => 1) if !$config;

  return ($config, $all, $record, $yearintitle, $limit, $info, $verbose, $debug);
}       

__END__

=head1 NAME
    
oai2mw.pl - Copy metadata from an OAI-PMH repository to a MediaWiki wiki
        
=head1 SYNOPSIS
            
oai2mw.pl -c myconfig.yaml

=head1 OPTIONS
              
=over 8

=item B<-c, --config>

Path to a config file in YAML format. 

=item B<-a, --all>

List the identifier and title of all records with a title. Can be combined with --limit.  

=item B<-r, --record>

Dump all info about one record identified by the given ID. 

=item B<-y, --yearintitle>

Include the year in the title of pages that are created in the wiki.

=item B<-l, --limit>

Max number of records to handle. 

=item B<-i, --info>

Display misc info about the given repository. 

=item B<-v, --verbose>

Turn on verbose output. 

=item B<-d, --debug>

Turn on debug output. 

=item B<-h, --help>

Print this documentation. 

=back
                                                               
=cut
