#!/opt/local/bin/perl -w

use Net::OAI::Harvester; 
use Data::Dumper;
use strict;

# create a harvester for the Library of Congress
my $harvester = Net::OAI::Harvester->new( 
    'baseURL' => 'http://telemarkskilder1.hit.no/dspace-oai/request'
);

## Find out the name for a repository
# my $identity = $harvester->identify();
# print "name: ",$identity->repositoryName(),"\n";

## List sets
# my $sets = $harvester->listSets();
# foreach ( $sets->setSpecs() ) { 
#   print "set spec: $_ ; set name: ", $sets->setName( $_ ), "\n";
# }

## List metadataformats
# my $list = $harvester->listMetadataFormats();
# print "archive supports metadata prefixes: ", join( ',', $list->prefixes() ),"\n";

## Get info about 1 record
# Web:     http://telemarkskilder1.hit.no/dspace/handle/123456789/2176?mode=full&submit_simple=Vis+fullstendig+innf%C3%B8rsel
# OAI-PMH: http://telemarkskilder1.hit.no/dspace-oai/request?verb=GetRecord&identifier=oai:telemarkskilder1.hit.no:123456789/2176&metadataPrefix=oai_dc
my $record = $harvester->getRecord( 
  identifier      => 'oai:telemarkskilder1.hit.no:123456789/2176',
  'metadataPrefix'    => 'oai_dc',
);

## get the Net::OAI::Record::Header object
my $header = $record->header();
print Dumper $header;

## get the metadata object 
my $metadata = $record->metadata();
print Dumper $metadata;

__END__

## list all the records in a repository
my $records = $harvester->listAllRecords( 
    'metadataPrefix'    => 'oai_dc' 
);
while ( my $record = $records->next() ) {
    my $header = $record->header();
    my $metadata = $record->metadata();
    print "identifier: ", $header->identifier(), "\n";
    print "title: ", $metadata->title(), "\n";
}

## GetRecord, ListSets, ListMetadataFormats also supported