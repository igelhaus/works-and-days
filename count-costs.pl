#!perl

#
# Counting costs based on svn commit logs
#

use 5.010;
use strict;
use warnings;

use Getopt::Long;
use File::Temp qw/tempfile/;
use XML::Twig;

sub which;
sub tmpfile;

my $range =  '';
my $path  = '.';

GetOptions(
	'r=s' => \$range,
	'p=s' => \$path ,
);

my $svn       = which('svn') // die 'Unable to locate svn command';
my $log_fname = tmpfile;

`$svn log --xml --revision $range $path >"$log_fname"`;

# at most one div will be loaded in memory
my $twig=XML::Twig->new(  
	twig_handlers => {
		logentry => sub {
			say $_->{att}{revision};
		},
		'logentry/author' => sub {
			say $_->text;
		}, # change para to p
	},
);
$twig->parsefile($log_fname);

unlink $log_fname;

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
