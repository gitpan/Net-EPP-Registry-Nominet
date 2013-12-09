#
#===============================================================================
#
#         FILE:  modify.t
#
#  DESCRIPTION:  Test of updates/modifications
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pete Houston (cpan@openstrike.co.uk)
#      COMPANY:  Openstrike
#      VERSION:  $Id: modify.t,v 1.2 2013/12/09 22:22:36 pete Exp $
#      CREATED:  28/03/13 14:58:33
#     REVISION:  $Revision: 1.2 $
#===============================================================================

use strict;
use warnings;

use Data::Dumper;
use Test::More;

if (defined $ENV{NOMTAG} and defined $ENV{NOMPASS}) {
	plan tests => 10;
} else {
	plan skip_all => 'Cannot connect to testbed without NOMTAG and NOMPASS';
}

use lib './lib';
use Net::EPP::Registry::Nominet;

my $epp = new_ok ('Net::EPP::Registry::Nominet', [ test => 1,
	user => $ENV{NOMTAG}, pass => $ENV{NOMPASS}, debug =>
	$ENV{DEBUG_TEST} || 0 ] );

is ($Net::EPP::Registry::Nominet::Code, 1000, 'Logged in');

warn $Net::EPP::Registry::Nominet::Error if
$Net::EPP::Registry::Nominet::Error;

BAIL_OUT ("Cannot login to EPP server") if
		$Net::EPP::Registry::Nominet::Error;

my $tag = lc $ENV{NOMTAG};

# change nameservers on a domain

my $okdomainname  = "ganymede-$tag.net.uk"; # valid
my $baddomainname = "nominet.org.uk";    # not valid

my $changes = {
	'add' => { 'ns' => ["ns1.caliban-$tag.lea.sch.uk", "ns1.macduff-$tag.co.uk"] },
	'rem' => { 'ns' => ["ns1.ganymede-$tag.net.uk"] },
	'chg' => {}
};

ok ($epp->modify_domain ($okdomainname, $changes),
	"Change nameservers on domain");

$changes = {
	'add' => {},
	'rem' => {},
	'chg' => {},
	'first-bill' => 'th',
	'recur-bill' => 'th',
	'auto-bill'  => 7,
	'auto-period'  => 5,
	'notes'      => ['This is the first note.', 'Here is another note.']
};

ok ($epp->modify_domain ($okdomainname, $changes),
	"Change extension fields on domain") or
	warn $epp->get_code . ' ' . $epp->get_reason;

$epp->modify_domain ($baddomainname, $changes);
isnt ($epp->get_code, 1000, "Change nameservers on invalid domain");

# change details of a registrant
my $cont = {
	'type'		=>	'FCORP',
	'trad-name'	=>	'American Industries',
	'co-no'		=>	'99998888',
	'opt-out'	=>	'N'
};

my $dominfo = $epp->domain_info ("duncan-$tag.co.uk");

ok ($epp->modify_contact ($dominfo->{registrant}, $cont),
	"Modify contact extras");

# change details of a contact (much the same as reg)
$cont = {
	postalInfo => { loc => {
		name	=>	'Bob "the Shred" Banker',
		addr	=>	{
			street	=>	['Bank Towers', '10 Big Bank Street'],
			city	=>	'London',
			sp		=>	'',
			pc		=>	'BB1 1XL',
			cc		=>	'GB'
		},
	}},
	voice	=>	'+44.7777777666',
	email	=>	'bankerbob@example.com'
};

ok ($epp->modify_contact ($dominfo->{registrant}, $cont),
	"Modify contact name/addr/phone/email");

# Change some details with UTF-8 chars

$cont->{postalInfo}->{loc}->{addr} = {
	street	=>	['75 Rue de la Mer'],
	city	=>	'Saint-André-de-Bâgé',
	sp	=>	'Ain',
	pc 	=>	'01332',
	cc	=>	'FR'
};
ok ($epp->modify_contact ($dominfo->{registrant}, $cont),
	"Modify utf8 contact");

# change details of a nameserver
# Get the current IPv6 address first
my $ns = "ns1.benedick-$tag.co.uk";
my $info = $epp->host_info ($ns);
#print Dumper ($info);
my $oldv6 = '';
for my $addr (@{$info->{addrs}}) {
	if ($addr->{version} and $addr->{version} eq 'v6') { $oldv6 = $addr->{addr}; last; }
}
if ($oldv6) {
	$changes = {
		'rem' => { 'addr' => [ { ip => $oldv6, version => "v6" } ] }
	};
} else {
	$changes = {
		'add' => { 'addr' => [ { ip => "1080:0:0:0:8:800:200C:417B", version => "v6" } ] },
	};
}

ok ($epp->modify_host ($ns, $changes), "Modify nameserver")
or warn $epp->get_reason;

ok ($epp->logout(), 'Logout');

exit;
