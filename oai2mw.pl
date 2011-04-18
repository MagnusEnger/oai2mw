#!/usr/bin/perl -w

use Net::OAI::Harvester;
use MediaWiki::Bot;
use Template;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use strict;

my ($baseurl, $all, $record, $limit, $info, $verbose, $debug) = get_options();

# Create a harvester
my $harvester = Net::OAI::Harvester->new( 
    'baseURL' => $baseurl,
);

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
$bot->set_wiki({
	host        => 'dt-test-wiki.websites.jonnybe.webdev.hit.no',
	path        => '',
}) or die "Could not set wiki";
# TODO make this configurable
$bot->login({
	username => 'Oai2mw',
	password => '',
}) or die "Login failed ", $bot->{'error'}->{'code'}, " ", $bot->{'error'}->{'details'};

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
while ( my $record = $records->next() ) {
	my $header = $record->header();
	my $metadata = $record->metadata();
	if ($metadata->title()) {
		my %record = metadata2structure($metadata);
		# Output
		my $text = '';
		$tt2->process('mwtemplate.tt', { 'rec' => \%record }, \$text) || die $tt2->error();
		$bot->edit({
			page    => $metadata->title(),
			text    => $text,
			summary => 'Lagt inn av oai2mw',
			# section => 'new',
		});
		$count++;
	}
  # Honour the --limit option
	if ($count == $limit) {
		last;
	}
}
print "$count records\n";

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
			$data{'coverage'} .= $1 . ", ";
			$data{'coverage_cat'} .= '[[Kategori:' . ucfirst($1) . ']] ';
		}
	}

	# Subjects
	my @subjects = $meta->subject();
	foreach my $subject (@subjects) {
		$data{'subjects'} .= $subject . ", ";
		$data{'subjects_cat'} .= '[[Kategori:' . ucfirst($subject) . ']] ';
	}

	return %data;

}

# Get commandline options
sub get_options {
  my $baseurl     = '';
	my $all         = '';
	my $record      = '';
  my $limit       = 0;
  my $info        = '';
  my $verbose     = '';
  my $debug       = '';
  my $help        = '';

  GetOptions("b|baseurl=s" => \$baseurl,
             "a|all"       => \$all, 
             "r|record=s"  => \$record, 
             "l|limit=i"   => \$limit,
             "i|info"      => \$info,
             "v|verbose"   => \$verbose,
             "d|debug"     => \$debug,
             "h|help"      => \$help,
             );
  
  pod2usage(-exitval => 0) if $help;
  pod2usage( -msg => "\nMissing Argument: -b, --baseurl required\n", -exitval => 1) if !$baseurl;

  return ($baseurl, $all, $record, $limit, $info, $verbose, $debug);
}       

__END__

=head1 NAME
    
oai2mw.pl - Copy metadata from an OAI-PMH repository to a MediaWiki wiki
        
=head1 SYNOPSIS
            
oai2mw.pl --info

=head1 OPTIONS
              
=over 8

=item B<-b, --baseurl>

Base URL of the OAI repo we want to talk to, e.g. http://example.org/dspace-oai/request 

=item B<-a, --all>

List the identifier and title of all records with a title. Can be combined with --limit.  

=item B<-r, --record>

Dump all info about one record identified by the given ID. 

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
