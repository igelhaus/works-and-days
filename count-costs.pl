#!perl

#
# Counting time costs based on svn commit logs:
#  * reads svn commit logs in xml format
#  * filters out commits by author(s)
#  * prints a CSV to STDOUT
#

use 5.010;
use strict;
use warnings;
use utf8;

use Getopt::Long;
use File::Temp qw/tempfile/;
use XML::Twig;

sub print_header;
sub new_commit_entry;
sub process_commit_entry;
sub which;
sub tmpfile;
sub error;

my $range   =  '';
my $path    = '.';
my $fname   =  '';
my $tracker =  '';
my @authors =  ();

GetOptions(
	'r=s' => \$range,
	'p=s' => \$path ,
	'f=s' => \$fname,
	't=s' => \$tracker,
	'a=s' => \@authors, # Filter out by author names
);

if (!length $range) {
	error(<<SYNOPSIS
USAGE

perl $0 -r rev1:rev2 [-p /path/to/svn/repository/root] [-f /path/to/svn/log.xml] [-t http://tracker-root.org/] [-a authorlogin]*
SYNOPSIS
	);
}

my $uses_tmpfile = 0;

if (length $fname && !-e -f -r) {
	error("Log file '$fname' is not accessible");
} elsif (!length $fname) {
	if (!-d "$path/.svn") {
		error("Unable to find Subversion repository in $path");
	}
	$uses_tmpfile = 1;
	$fname        = tmpfile;
	my $svn       = which('svn') // error('Unable to locate svn command and log file is not specified');
	`$svn log --xml --revision $range $path >"$fname"`;
}

if (-z $fname) {
	unlink $fname if $uses_tmpfile;
	error('Log file is empty');
}

print_header;

my $commit = new_commit_entry;
my $twig   = XML::Twig->new(twig_handlers => {
	logentry => sub {
		$commit->{number} = $_->{att}{revision};
		process_commit_entry($commit);
		$commit = new_commit_entry;
	},
	'logentry/author' => sub { $commit->{author} = $_->text; },
	'logentry/date'   => sub { $commit->{date}   = $_->text; },
	'logentry/msg'    => sub {
		my $message = $_->text;
		while ($message =~ /#(\d+)/sg) {
			push @{$commit->{tickets}}, $1;
		}
		while ($message =~ /(?:время|time):\s*([.,\d]+)\s*(?:ч(?:\.|ас(?:\.|а|ов)?)|h(?:ours?)?)/sgi) {
			$commit->{spent} += $1;
		}
		while ($message =~ /(?:время|time):\s*([.,\d]+)\s*(?:м\.?|мин\.?|минут|минуты|m\.?|min\.?|minutes)/sgi) {
			$commit->{spent} += 0+ sprintf q/%.02f/, $1/60;
		}
	},
});
$twig->parsefile($fname);

unlink $fname if $uses_tmpfile;

exit;

sub print_header
{
	say join ',', (
		'Commit'            ,
		'Commit Date'       ,
		'Commit Author'     ,
		'Time Spent (hours)',
		'Affected Ticket(s)',
	);
}

sub new_commit_entry
{
	return {
		number  =>  0,
		date    => '',
		author  => '',
		spent   =>  0,
		tickets => [],
	};
}

# NB! Currently we assume trac only when formatting URLs
sub process_commit_entry
{
	my $commit  = shift;
	
	if (@authors && !grep { $_ eq $commit->{author} } @authors) {
		return;
	}
	
	my $commit_id = length($tracker)? $tracker . '/changeset/' . $commit->{number} : $commit->{number};
	my ($date)    = ($commit->{date} =~ /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/);
	my $tickets   = join ' ', map {
		length($tracker)? $tracker . '/ticket/' . $_ : $_;
	} @{$commit->{tickets}};
	say join ',', ($commit_id, $date, $commit->{author}, $commit->{spent}, $tickets);
	
	return 1;
}

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

sub error
{
	my $message = shift // '';
	say STDERR $message;
	exit 1;
}
