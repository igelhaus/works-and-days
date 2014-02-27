#!perl

#
# Counting costs based on svn commit logs
#

use 5.010;
use strict;
use warnings;
use utf8;

use Getopt::Long;
use File::Temp qw/tempfile/;
use XML::Twig;

sub which;
sub tmpfile;

my $range =  '';
my $path  = '.';
my $fname =  '';

GetOptions(
	'r=s' => \$range,
	'p=s' => \$path ,
	'f=s' => \$fname,
);

if (!length $fname) {
	$fname  = tmpfile;
	my $svn = which('svn') // die 'Unable to locate svn command and log file is not specified';
	`$svn log --xml --revision $range $path >"$fname"`;
}

my $commit = {};
my $twig   = XML::Twig->new(  
	twig_handlers => {
		logentry => sub {
			$commit->{number} = $_->{att}{revision};
			say join ', ', (
				$commit->{number},
				$commit->{date}  ,
				$commit->{author},
				$commit->{time}  ,
				join('; ', @{$commit->{tickets}}),
			);
		},
		'logentry/author' => sub { $commit->{author} = $_->text; },
		'logentry/date'   => sub { $commit->{date}   = $_->text; },
		'logentry/msg'    => sub {
			my $message        = $_->text;
			$commit->{tickets} = [];
			$commit->{time}    =  0;
			while ($message =~ /#(\d+)/sg) {
				push @{$commit->{tickets}}, $1;
			}
			while ($message =~ /(?:время|time):\s*([.,\d]+)\s*(?:ч(?:\.|ас(?:\.|а|ов)?)|h(?:ours?)?)/sgi) {
				$commit->{time} += $1;
			}
		},
	},
);
$twig->parsefile($fname);

#unlink $fname;

exit;

#
# Simple non-portable implementation of `which` command:
#
sub which
{
	my $command = shift // return;
	my @paths   = split /:/, $ENV{PATH};
	foreach my $path (@paths) {
		return "$path/$command" if -f -x "$path/$command";
	}
	return;
}

sub tmpfile
{
	(undef, my $fname) = File::Temp::tempfile('count-costs-XXXXXXXXXX', TMPDIR => 1, OPEN => 0);
	return $fname;
}
