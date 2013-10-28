#
#===============================================================================
#
#         FILE:  renew.t
#
#  DESCRIPTION:  Test of renewals
#
#        FILES:  ---
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pete Houston (cpan@openstrike.co.uk)
#      COMPANY:  Openstrike
#      VERSION:  $Id: renew.t,v 1.1.1.1 2013/10/21 14:04:54 pete Exp $
#      CREATED:  04/02/13 17:15:33
#     REVISION:  $Revision: 1.1.1.1 $
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

is ($Net::EPP::Registry::Nominet::Code, 1000, 'Logged in');

warn $Net::EPP::Registry::Nominet::Error if
$Net::EPP::Registry::Nominet::Error;

BAIL_OUT ("Cannot login to EPP server") if
		$Net::EPP::Registry::Nominet::Error;

my $tag = lc $ENV{NOMTAG};

my $renewit = {name => "duncan-$tag.co.uk"};
my $newexpiry = $epp->renew ($renewit) || $epp->get_reason;

like ($newexpiry, qr/^\d\d\d\d-|^V128/, 'Plain renewal');

$renewit = {name => "horatio-$tag.co.uk", period => 10};
$newexpiry = $epp->renew ($renewit) ||
	$epp->get_reason;

like ($newexpiry, qr/^\d\d\d\d-|^V128/, '10-year renewal');

# Unrenew here
my $datesref = undef;
my $dom = "lysander-$tag.co.uk";

$datesref = $epp->unrenew ($dom, "duncan-$tag.co.uk");
my $reason = $epp->get_reason;
like ($datesref->{$dom} || $reason, qr/^\d\d\d\d-|V270/, 'Multiple domain unrenewal') or warn "Reason: ". $epp->get_reason . "\n";

$dom = "horatio-$tag.co.uk";
$datesref = $epp->unrenew ($dom);
$reason = $epp->get_reason;
like ($reason, qr/^V273/, 'Bad domain unrenewal') or warn $reason;

ok ($epp->logout(), 'Logout successful');

exit;

