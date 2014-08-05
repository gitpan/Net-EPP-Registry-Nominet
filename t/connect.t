#
#===============================================================================
#
#         FILE:  connect.t
#
#  DESCRIPTION: Test of connection to Nominet EPP servers
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  Must have set $NOMTAG and $NOMPASS env vars first
#       AUTHOR:  Pete Houston (cpan@openstrike.co.uk)
#      COMPANY:  Openstrike
#      VERSION:  $Id: connect.t,v 1.5 2014/08/04 17:33:14 pete Exp $
#      CREATED:  04/02/13 11:54:43
#     REVISION:  $Revision: 1.5 $
#===============================================================================

use strict;
use warnings;

use Test::More tests => 15;

use lib './lib';

BEGIN { use_ok ('Net::EPP::Registry::Nominet') }

my $epp;
my %newargs = (
	test => 1,
	login => 0,
	user => $ENV{NOMTAG}, pass => $ENV{NOMPASS},
	debug => $ENV{DEBUG_TEST} || 0,
#	def_years => 'holiday',
	timeout	=>	[ 'dog', 'cat' ]
);

# warnings if not using the svn net-epp. Avoid this!!!
{
	no warnings 'once';
	$Net::EPP::Protocol::THRESHOLD = 10000000; # 10 MB
}
$epp = Net::EPP::Registry::Nominet->new (%newargs);

SKIP: {
	skip "No access to testbed from this IP address", 3 unless defined $epp;

	ok ($epp->{def_years} == 2, 'def_years validation');

	$epp = new_ok ('Net::EPP::Registry::Nominet', [
		test  => 1,
		login => 0,
		debug => $ENV{DEBUG_TEST} || 0 ]
	);

	is ($epp->login ('nosuchuser', 'nosuchpass'), undef,
		'Login with duff user');
}

SKIP: {
	skip "NOMTAG/NOMPASS not set", 11 unless (defined $ENV{NOMTAG} and defined $ENV{NOMPASS});

	isnt ($epp->login ($ENV{NOMTAG}, $ENV{NOMPASS}), undef, 'Login with good credentials');

	is ($Net::EPP::Registry::Nominet::Code, 1000, 'Logged in');
	
	warn $Net::EPP::Registry::Nominet::Error if
		$Net::EPP::Registry::Nominet::Error;

	BAIL_OUT ("Cannot login to EPP server") if
		$Net::EPP::Registry::Nominet::Error;

	ok ($epp->hello(), 'Hello');
	ok ($epp->ping(), 'Ping');
	ok ($epp->logout(), 'Logout');
	ok ((not defined $epp->hello()), 'Hello attempt when logged out');
	$newargs{login} = 1;
	$epp = Net::EPP::Registry::Nominet->new (%newargs);
	ok (defined $epp, 'Reconnect and Login with good credentials');
	$epp->logout;
	$newargs{login}    = 0;
	$newargs{verify}   = 1;
	$newargs{testssl}  = 1;
	$newargs{ca_file}  = '/foo';
	$epp = Net::EPP::Registry::Nominet->new (%newargs);
	ok ((not defined $epp), 'Reconnect with duff SSL cert verification');
	$newargs{ca_file}  = 't/ca.crt';
	$epp = Net::EPP::Registry::Nominet->new (%newargs);
	ok (defined $epp, 'Reconnect with good SSL cert verification');
	$newargs{verify}   = 0;
	$newargs{ciphers}  = 'duff';
	$epp = Net::EPP::Registry::Nominet->new (%newargs);
	ok ((not defined $epp), 'Reconnect with duff cipher list');
	$newargs{ciphers}  = 'HIGH:!ADH:!MEDIUM:!LOW:!SSLv2:!EXP';
	$epp = Net::EPP::Registry::Nominet->new (%newargs);
	ok (defined $epp, 'Reconnect with good cipher list');
};

exit;
