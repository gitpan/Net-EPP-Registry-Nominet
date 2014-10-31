#
#===============================================================================
#
#         FILE:  query.t
#
#  DESCRIPTION:  Query domain info
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pete Houston (cpan@openstrike.co.uk)
#      COMPANY:  Openstrike
#      VERSION:  $Id: query.t,v 1.2 2014/10/31 16:51:00 pete Exp $
#      CREATED:  04/02/13 15:01:59
#     REVISION:  $Revision: 1.2 $
#===============================================================================

use strict;
use warnings;

use Test::More;

if (defined $ENV{NOMTAG} and defined $ENV{NOMPASS}) {
	plan tests => 7;
} else {
	plan skip_all => 'Cannot connect to testbed without NOMTAG and NOMPASS';
}

use lib './lib';
use Net::EPP::Registry::Nominet;

my $epp = new_ok ('Net::EPP::Registry::Nominet', [ test => 1,
	user => $ENV{NOMTAG}, pass => $ENV{NOMPASS}, debug =>
	$ENV{DEBUG_TEST} || 0 ] );

my $tag = lc $ENV{NOMTAG};

# Domains
my $info = $epp->domain_info ("duncan-$tag.co.uk");

like ($info->{exDate}, qr/^\d\d\d\d-/, 'Correct domain info');
my $reg = $info->{registrant};
my $ns  = $info->{ns};

$info = $epp->domain_info ("duncan-$tag.co.uk", undef, 1);

like ($info->{exDate}, qr/^\d\d\d\d-/, 'Correct domain info with follow');

$info = $epp->domain_info ("ophelia-$tag.co.uk");
like ($info->{exDate}, qr/^\d\d\d\d-/, 'Correct domain info with DNSSEC');

# Contacts
$info = $epp->contact_info ($reg);
like ($info->{crDate}, qr/^\d\d\d\d-/, 'Correct contact info');

# Hosts
$info = $epp->host_info ($ns->[0]);
is ($info->{clID}, $ENV{NOMTAG}, 'Correct host info');

ok ($epp->logout(), 'Logout successful');

exit;
