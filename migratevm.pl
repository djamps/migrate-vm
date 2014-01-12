#!/usr/bin/perl
use strict;
use File::Basename qw( dirname );
use lib dirname(__FILE__).'/lib';
use Xen::API;
use Data::Dumper;
use Getopt::Long;

## Setup command line options
my $opt = {};
GetOptions ( $opt,
	"configfile=s",
	"shost=s",
	"suser=s",
	"spass=s",
	"svm=s",
	"dhost=s",
	"duser=s",
	"dpass=s",
	"dsr=s",
	"debug!",
);

my $version = "1.0.1";
print "migratevm $version started\n";

## Set up vars
my $shost = $opt->{'shost'} || Xen::API::input("Enter source host name/IP (blank = localhost): ") || 'localhost';
my $suser = $opt->{'suser'} || Xen::API::input("Enter username for ".$shost." (blank = root): ") || 'root';
my $spass = $opt->{'spass'} || Xen::API::password("Enter password for ".$shost.": ");
my $svm = $opt->{'svm'} || Xen::API::input("Enter source vm name or uuid on $shost: ");
my $dhost = $opt->{'dhost'} || Xen::API::input("Enter destination host name/IP (blank = localhost): ") || 'localhost';
my $duser = $opt->{'duser'} || Xen::API::input("Enter username for ".$dhost." (blank = root): ") || 'root';
my $dpass = $opt->{'dpass'} || Xen::API::password("Enter password for ".$dhost.": ");
my $dsr = $opt->{'dsr'} || Xen::API::input("Destination SR on ".$dhost." (blank for default): ");

## Create Xen::API object on source host
print "Connecting to source host\n";
my $x = Xen::API->new($shost,$suser,$spass) || die $!;

## Do the transfer
print "Connecting to destination host and Starting transfer\n";
$x->transfer_vm($svm,$dhost,$duser,$dpass,$dsr);

exit;
