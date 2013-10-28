# $Id: Makefile.PL,v 1.1.1.1 2013/10/21 14:04:54 pete Exp $
use ExtUtils::MakeMaker;
use strict;
use warnings;

my %MF = (
	NAME            => 'Net::EPP::Registry::Nominet',
	ABSTRACT		=> 'EPP client code for Nominet',
	AUTHOR			=> 'Pete Houston (cpan@openstrike.co.uk)',
	BUILD_REQUIRES	=> {
		'Test::More'	=>	'0',
	},
	LICENSE			=> 'perl',
	PREREQ_PM		=>	{
		'Net::EPP'	=>	'0.19',
		'Carp'		=>	'0',
	},
	VERSION_FROM    => 'lib/Net/EPP/Registry/Nominet.pm'
);
if ($ExtUtils::MakeMaker::VERSION lt 6.55) { delete $MF{BUILD_REQUIRES}; }
if ($ExtUtils::MakeMaker::VERSION lt 6.31) { delete $MF{LICENSE}; }
WriteMakefile (%MF);
unless (exists $ENV{NOMTAG} and exists $ENV{NOMPASS}) {
	print <<EOT;

It is *highly* recommended that you set the environment variables NOMTAG
and NOMPASS to be your tag name and password respectively for the
Nominet EPP testbed prior to running "make test". Doing so allows the
full suite of tests to be run. See
http://registrars.nominet.org.uk/registration-and-domain-management/registrar-systems/epp/testbed
for details of the testbed and how to register for it.

EOT
}
