#    $Id: Nominet.pm,v 1.6 2014/08/04 17:42:21 pete Exp $
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
################################################################################
package Net::EPP::Registry::Nominet;

use strict;
use warnings;

# use other modules
use Net::EPP::Frame;
use Carp;

use base qw(Net::EPP::Simple);
use constant EPP_XMLNS	=> 'urn:ietf:params:xml:ns:epp-1.0';
use vars qw($Error $Code $Message);

BEGIN {
	our ($VERSION, @ISA);
	$VERSION    = '0.01_02';
	@ISA        = qw(Net::EPP::Simple Exporter);
}

# file-scoped lexicals
my $Host      = 'epp.nominet.org.uk';
my $Hosttest  = 'testbed-epp.nominet.org.uk';
my $EPPVer    = '1.0';
my $EPPLang   = 'en';
my $NSVer     = '2.0';
my $Debug     = 0;

=pod

=head1 Name

Net::EPP::Registry::Nominet - a simple client interface to Nominet EPP
jobs

=head1 Synopsis

	#!/usr/bin/perl
	use strict;
	use Net::EPP::Registry::Nominet;

	my $epp = Net::EPP::Registry::Nominet->new (
		user  =>  'MYTAG',
		pass  =>  'mypass'
	) or die ('Could not login to EPP server: ', $epp->get_error);

	my $dom = 'foo.co.uk';
	
	if ($epp->check_domain($dom) == 1) {
		print "Domain $dom is available\n" ;
	} else {
		my $info = $epp->domain_info($dom);
		my $res  = $epp->renew_domain ({
			name         => $dom,
			cur_exp_date => $info->{exDate},
			period       => 5
		});
		if ($res) {
			print "$dom renewed; new expiry date is $res\n";
		} else {
			warn "Unable to renew $dom: " . $epp->get_reason;
		}
	}

=head1 Description

L<Nominet|http://www.nominet.org.uk/> is the organisation in charge of
domain names under the .uk TLD.  Historically it used cryptographically
signed email communications with registrars to provision domains (and
still does). More recently (since 2010) it has instituted an EPP system
which is sufficiently different from standard EPP that none of the
standard modules will work seamlessly with it.

This module exists to provide a client interface to the Nominet EPP
servers. It is a subclass of L<Net::EPP::Simple> and aims to adhere
closely to that interface style so as to act as a drop-in replacement.

=cut

END {}

# subs and methods

=pod

=head1 Constructor

	my $epp = Net::EPP::Registry::Nominet->new (
		user  =>  'MYTAG',
		pass  =>  'mypass'
	) or die ('Could not login to EPP server: ', $epp->get_error);

The constructor for C<Net::EPP::Registry::Nominet> has the same
general form as the one for C<Net::EPP::Simple>, but with the following
exceptions:

=over

=item * If C<test> is set but C<testssl> is not, C<port> defaults to 8700

=item * if C<test> is set, C<host> defaults to 'testbed-epp.nominet.org.uk'. Otherwise C<host> defaults to 'epp.nominet.org.uk'.

=item * C<timeout> defaults to 5 (seconds).

=item * C<debug> specifies the verbosity. 0 = almost silent, 1 = displays
warnings/errors, 2 = displays EPP frames in over-ridden methods. Default
is 0.

=item * C<def_years> changes the default number of years for
registrations and renewals from the system default of 2. This is only
used if no explicit number of years is given in each registration or
renewal command. It must be an integer between 1 and 10 inclusive (but
note that renewing for 10 years pre-expiry will always fail because
Nominet prohibits it).

=item * There is no facility for a config file but this may be added in
future versions.

=item * There is no facility for supplying SSL client certificates
because there is no support for them in the Nominet EPP server.

=back

=cut

sub new {
	my ($class, %params) = @_;

	# Set the (deprecated) flag for XML responses. Should be the
	# grandparent default anyway these days, but useful if someone tries
	# to use with old version of Net::EPP.
	$params{dom}		 = 1;

	if (defined $params{debug}) { $Debug = $params{debug}; }
	if ($params{test} and $params{test} == 1) {
		# Use test server
		if ($params{testssl} and $params{testssl} == 1) {
			$params{port} = 700;
			$params{ssl}  =   1;
		} else {
			$params{port} = 8700;
			$params{ssl}  = undef;
		}
		$params{host} = $Hosttest;
	} else {
		# Use live server
		$params{port} = 700;
		$params{ssl}  =   1;
		$params{host} = $Host;
	}
	$params{timeout}	= (int($params{timeout} || 0) > 0 ? $params{timeout} : 5);
	if ($params{ssl} and $params{verify}) {
		$params{SSL_ca_file}      ||= $params{ca_file};
		$params{SSL_ca_path}      ||= $params{ca_path};
		$params{SSL_verify_mode}  =   0x01;
	}
	if ($params{ssl} and $params{ciphers}) {
		$params{SSL_cipher_list} = $params{ciphers};
	}

	my $self = Net::EPP::Client->new(%params);
	unless ($self->{timeout}) { $self->{timeout} = $params{timeout}; }

	# Set the default years.
	$self->{def_years} = 2;
	if (defined $params{def_years}) {
		my $years = scalar $params{def_years};
		if ($years and $years =~ /^[0-9]+$/) {
			if ($years > 0 and $years < 11) {
				$self->{def_years} = $years;
			} else {
				carp "Supplied parameter def_years is not between 0 and 11";
			}
		} else {
			carp "Supplied parameter def_years is not an integer";
		}
	}
	$self->{authenticated}  = 0;
	$self->{reconnect}      ||= 3; # Upwards compatibility

	bless($self, $class);

	# Connect to server
	eval { $self->{greeting} = $self->connect (%params); };
	unless ($self->{greeting}) {
		$self->{connected} = 0;
		warn 'No greeting returned: cannot continue';
		warn ($@) if $@;
		return undef;
	}
	$self->{connected}      = 1;

	# Login
	unless (defined $params{login} and $params{login} == 0) {
		$self->login ($params{user}, $params{pass});
	}

	# If there was an error in the constructor, there's no point
	# continuing - return undef just like Net::EPP::Simple
	return $Error ? undef : $self;
}

=pod

=head1 Login

The client can perform a standalone EPP Login if required.

	$epp->login ($username, $password, $opt_ref)
		or die ("Could not login: ", $epp->get_reason);

The optional third argument, C<$opt_ref>, is a hash ref of login
options. Currently the only supported option is 'nominet_schemas' which
should be set to a true value if the user requires the old, deprecated
Nominet EPP schemas. These were removed from the Live systems before
August 2013, so should not be retained in production code.

=cut

sub login {
	my ($self, $user, $pass, $options) = @_;

	# Set login frame
	my $login = Net::EPP::Frame::Command::Login->new;

	$login->clID->appendText($user);
	$login->pw->appendText($pass);
	$login->version->appendText($EPPVer);
	$login->lang->appendText($EPPLang);

	my $objects = $self->{greeting}->getElementsByTagNameNS(EPP_XMLNS, 'objURI');
	#while (my $object = $objects->shift) {
	#for my $ns ('nom-account', 'nom-contact', 'nom-domain',


	if ($options->{'nominet_schemas'}) {
		# Deprecated
		for my $ns ('nom-domain', 'nom-notifications') {
			my $el = $login->createElement('objURI');
			$el->appendText("http://www.nominet.org.uk/epp/xml/$ns-$NSVer");
			$login->svcs->appendChild($el);
		}
		my $foo = $login->createElement('objURI');
		$foo->appendText("urn:ietf:params:xml:ns:host-1.0");
		$login->svcs->appendChild($foo);
	} else {
		# Standard schemas and extensions
		for my $ns ('epp', 'eppcom', 'domain', 'host', 'contact') {
			my $el = $login->createElement('objURI');
			$el->appendText("urn:ietf:params:xml:ns:$ns-$EPPVer");
			$login->svcs->appendChild($el);
		}
		# Extensions go here
		my $ext = $login->createElement('svcExtension');
		for my $ns (qw/domain-nom-ext-1.2 contact-nom-ext-1.0
		std-notifications-1.2 std-warning-1.1 std-contact-id-1.0
		std-release-1.0 std-handshake-1.0 nom-abuse-feed-1.0
		std-fork-1.0 std-list-1.0 std-locks-1.0 std-unrenew-1.0
		nom-direct-rights-1.0/) {
			my $el = $login->createElement('extURI');
			$el->appendText("http://www.nominet.org.uk/epp/xml/$ns");
			$ext->appendChild($el);
		}
		$login->svcs->appendChild($ext);
	}

	my $response = $self->_send_frame ($login);

	if ($Code != 1000) {
		$Error = "Error logging in (response code $Code)";
		return undef;
	}

	$self->{authenticated} = 1;
	return $self;
}

=head1 Availability checks

The availability checks work similarly to C<Net::EPP::Simple> except
that they return an array with three elements. The first element is the
availability indicator as before (0 if provisioned, 1 if available,
undef on error) and the second element is the abuse counter which shows
how many more such checks you may run. This counter is only relevant
for check_domain and will always be undef for the other check methods.
The third element is an indicator of the rights to register the domain.
This is only relevant for check_domain and if the domain being checked
is a second-level domain in which case the value will be the domain with
the rights and undef if there are no rights.

	my ($avail, $left, $rights) = $epp->check_domain ("foo.uk");
	$avail = $epp->check_contact ("ABC123");
	$avail = $epp->check_host ("ns0.foo.co.uk");

=cut

sub _check {
	my ($self, $type, $identifier) = @_;

	# If there's nothing to check, don't bother asking the server
	unless (defined $identifier) {
		$Error = "Missing identifier as argument";
		carp $Error;
		return undef;
	}

	my $frame;
	my @spec = $self->spec ($type);
	my $key = $type eq 'contact' ? 'id' : 'name';
	if ($type eq 'domain' or $type eq 'contact' or $type eq 'host') {
		$frame = Net::EPP::Frame::Command::Check->new;
		my $obj  = $frame->addObject (@spec);
		my $name = $frame->createElement ("$type:$key");
		$name->appendText ($identifier);
		$obj->appendChild ($name);
		$frame->getCommandNode->appendChild ($obj);
	} else {
		$Error = "Unknown object type '$type'";
		warn $Error if $Debug;
		return undef;
	}

	my $response = $self->_send_frame ($frame) or return undef;

	my $extra = $response->getNode("$type-nom-ext:chkData");
	my $count = undef;
	$count = $extra->getAttribute('abuse-limit') if defined $extra;
	warn "Remaining checks = $count\n" if ($Debug and defined $count);

	my $rights = undef;
	if ($type eq 'domain' and $identifier !~ /\..*\./) {
		$extra  = $response->getNode("nom-direct-rights:ror")->firstChild;
		$rights = $extra->toString if defined $extra;
	}

	return ($response->getNode($spec[1], $key)->getAttribute('avail'), $count, $rights);
}

=head1 Domain Renewal

You can renew an existing domain with the renew() command.

	my $new_expiry = $epp->renew ({
		name          => $domstr,
		cur_exp_date  => $old_expiry,
		period        => $years
	});

On success, C<$new_expiry> contains the new expiry date in long form.
Otherwise returns undef.

C<$domstr> is just the domain as a string, eg. "foo.co.uk".

If you do not specify the old expiry date in your request, the system
will attempt to retrieve it from the registry first. It should be in the
form YYYY-MM-DD.

C<$years> must be an integer between 1 and 10 inclusive and defaults to any
value specified in the constructor or 2 otherwise. 10 year renewals must
be post-expiry.

=cut

sub renew {
	my ($self, $renew) = @_;
	my $domain = $renew->{name};
	my $expiry = $renew->{cur_exp_date};
	my $years  = $renew->{period};
	my @spec   = $self->spec ('domain');
	my $frame  = Net::EPP::Frame::Command::Renew->new;
	my $obj    = $frame->addObject (@spec);
	my $name   = $frame->createElement ('domain:name');
	$name->appendText ($domain);
	$obj->appendChild ($name);

	unless (defined $expiry and $expiry =~ /^2\d\d\d-\d\d-\d\d$/) {
		warn "Badly defined expiry (" . ($expiry || '') . ") - retrieving from registry" if $Debug;
		my $dominfo = $self->domain_info ($domain);
		unless ($dominfo->{exDate} and
			$dominfo->{exDate} =~ /^2\d\d\d-\d\d-\d\d/) {
			$Error = "Unable to get expiry date from registry for $domain";
			warn $Error;
			return undef;
		}
		$expiry = substr($dominfo->{exDate}, 0, 10);
	}
	$name = $frame->createElement ('domain:curExpDate');
	$name->appendText ($expiry);
	$obj->appendChild ($name);

	$years ||= $self->{def_years};
	$name = $frame->createElement ('domain:period');
	$name->appendText ($years);
	$name->setAttribute ('unit', 'y');
	$obj->appendChild ($name);

	$frame->getCommandNode->appendChild ($obj);

	if (my $response = $self->_send_frame ($frame)) {
		my $date = $response->getNode ($spec[1], 'exDate')->firstChild->toString ();
		warn "New expiry date = $date\n" if $Debug;
		return $date;
	}
	return undef;
}

=head1 Domain Unrenewal

You can unrenew a list of recently renewed domains with the unrenew() command.

	my $new_expiry = $epp->unrenew ($domstr, $domstr2, ... )

On success, C<$new_expiry> is a hashref with the domain names as keys and
the new expiry dates in long form as the values.
Otherwise returns an empty hashref or undef on complete failure.

C<$domstr>, C<$domstr2> are just the domains as a string, eg. "foo.co.uk".

=cut

sub unrenew {
	my ($self, @doms) = @_;

	my $type   = 'u';
	my @spec   = $self->spec ($type);
	my $frame  = Net::EPP::Frame::Command::Update->new;

	my $elem   = $frame->createElement ('u:unrenew');
	$elem->setAttribute ("xmlns:$type", $spec[1]);

	for my $domain (@doms) {
		my $name = $frame->createElement ('u:domainName');
		$name->appendText ($domain);
		$elem->appendChild ($name);
	}
	$frame->getCommandNode->appendChild ($elem);

	if (my $response = $self->_send_frame ($frame)) {
	
		# Results not necessarily returned by EPP in the same order.
		# Construct a hash ref with domains as keys and expiry dates as
		# values
		my $dates = {};
		for my $node ($response->getElementsByLocalName ('renData')) {
			my $dom = $node->getChildrenByLocalName('name')->[0]->firstChild->toString;
			my $exp = $node->getChildrenByLocalName('exDate')->[0]->firstChild->toString;
			$dates->{$dom} = $exp;
		}
		return $dates;
	}
	return undef;
}

=head1 Release domains

To transfer a domain to another registrar, use the release_domain
method. Returns 1 on success (including success pending handshake), 0 on
failure

	my $res = $epp->release_domain ('foo.co.uk', 'OTHER_TAG');
	if ($res) {
		if ($epp->get_code == 1001) {
			warn "Handshake pending\n";
		}
	} else {
		warn "Could not release $dom: ", $epp->get_reason;
	}

=cut

# This does not fit well with Standard EPP, so we need to create our own
# command frame from scratch
sub release_domain {
	my ($self, $domain, $tag) = @_;
	my $frame;
	my $type = 'r';
	my @spec = $self->spec ($type);
	$frame = Net::EPP::Frame::Command::Update->new;

	my $elem = $frame->createElement ('r:release');
	$elem->setAttribute ("xmlns:$type", $spec[1]);

	my $name = $frame->createElement ('r:domainName');
	$name->appendText ($domain);
	$elem->appendChild ($name);

	$name = $frame->createElement ('r:registrarTag');
	$name->appendText ($tag);
	$elem->appendChild ($name);
	$frame->getCommandNode->appendChild ($elem);

	my $response = $self->_send_frame ($frame);
	if ($Code > 999 and $Code < 1002) { return 1; }
	return 0;
}

=head1 Create objects

Standard EPP allows the creation of domains, contacts and hosts
(nameservers). The same is true of Nominet's version, with several
differences.

=head2 Register domains

To register a domain, there must already be a registrant in the system.
You will need to create a hashref of the domain like this to perform the
registration.


	my $domain = {
		name         => "foo.co.uk",
		period       => "5",
		registrant   => "ABC123",
		nameservers  => {
			'nsname0'  => "ns1.bar.co.uk",
			'nsname1'  => "ns2.bar.co.uk"
		}
	};
	my ($res) = $epp->create_domain ($domain);
	if ($res) {
		print "Expiry date of new domain: $res->{expiry}\n";
	} else {
		warn "Domain not registered: ", $epp->get_reason, "\n";
	}

It returns undef on failure, 1 on success in scalar context and a
hashref on success in list context. Only the keys "expiry" and "regid"
in this hashref are populated so far.

To register a new domain to a new registrant you can either create the
registrant first to get the ID or you can replace the 'registrant' value
in the C<$domain> with a hashref of the registrant and C<create_domain()> will
create the registrant first as a handy shortcut.

The alias C<register()> can be used in place of C<create_domain()>.

=cut

sub register {
	my $self = shift;
	return $self->create_domain (@_);
}

sub create_domain {
	my ($self, $domain) = @_;

	# New contact? Register them first
	if (ref $domain->{registrant}) {
		my $contyes = $self->create_contact ($domain->{registrant});
		if ($contyes and $contyes == 1) {
			$domain->{registrant} = $domain->{registrant}->{id};
		} else {
			return undef;
		}
	}

	my $frame;
	my @spec = $self->spec ('domain');
	$frame = Net::EPP::Frame::Command::Create->new;
	my $obj  = $frame->addObject (@spec);
	my $name = $frame->createElement ('domain:name');
	$name->appendText ($domain->{name});
	$obj->appendChild ($name);

	# Set the duration - integral years only
	my $years = $domain->{period};
	$years ||= $self->{def_years};
	$name = $frame->createElement ('domain:period');
	$name->appendText ($years);
	$name->setAttribute ('unit', 'y');
	$obj->appendChild ($name);


	# Add in the nameservers, if any
	my $ns = $domain->{nameservers};
	if (scalar keys %$ns) {
		my @hostspec = $self->spec ('host');
		$name = $frame->createElement ('domain:ns');
		$name->setNamespace ($hostspec[1], 'ns', 0);
		for my $i (0..9) {
			if ($ns->{"nsid$i"}) {
				# Not used anymore. Logic kept in case Nominet reverse their
				# decision
				$self->_add_nsid ($name, $frame, $ns->{"nsid$i"});
			} elsif ($ns->{"nsname$i"}) {
				$self->_add_nsname ($name, $frame, $ns->{"nsname$i"});
			}
		}
		$obj->appendChild ($name);
	}

	# Set up the registrant
	$name = $frame->createElement ('domain:registrant');
	$name->appendText ($domain->{registrant});
	$obj->appendChild ($name);

	# add auth
	# Crazily, this element must be present to pass the XML checks, but
	# after detecting its presence, Nominet subsequently ignores it.
	$name = $frame->createElement ('domain:authInfo');
	my $pw = $frame->createElement ('domain:pw');
	$pw->appendText ('dummyvalue');
	$name->appendChild ($pw);
	$obj->appendChild ($name);

	# Request complete, so send the frame
	$frame->getCommandNode->appendChild ($obj);

	my $response = $self->_send_frame ($frame);
	return undef unless $Code == 1000;
	my $date = $response->getNode ($spec[1], 'exDate')->firstChild->toString ();
	warn "expiry date = $date\n" if $Debug;

	# Perhaps this return should use wantarray instead?
	return @{[{ expiry => $date, regid => $domain->{registrant} }]};
}

=head2 Register accounts

To register an account, you will need to create a hashref of the
account like this to perform the registration.

	my $registrant = {
		'id'          => "ABC123",
		'name'        => 'Example Company',
		'trad-name'   => 'Examples4u',
		'type'        => 'LTD',
		'co-no'	      => '12345678',
		'opt-out'     => 'n',
		'postalInfo'  => { loc => {
			'name'  => 'Arnold N Other',
			'org'   => 'Example Company',
			'addr'  => {
				'street'  => ['555 Carlton Heights'],
				'city'    => 'Testington',
				'sp'      => 'Testshire',
				'pc'      => 'XL99 9XL',
				'cc'      => 'GB'
			}
		}},
		'voice'  => '+44.1234567890',
		'email'  => 'a.n.other@example.com'
	};
	my $res = $epp->create_contact ($registrant) or die $epp->get_reason;

It returns undef on failure, 1 on success. The new id must be unique
(across the entire registry) otherwise the creation will fail. If no id
is specified a random one will be used instead and can subsequently be
extracted as C<$registrant-E<gt>{id}> in the calling code.

=cut

# Nominet now only has one contact per registrant, so this is
# effectively creating a new registrant.
sub create_contact {
	my ($self, $contact) = @_;

	# Use random id if none supplied
	$contact->{id} ||= $self->random_id;
	$contact->{authInfo} ||= 12345;
	unless (defined $contact->{fax}) { $contact->{fax} = ''; }
	unless (defined $contact->{voice}) {
		$Error = "Missing contact phone number";
		return undef;
	} elsif (not $self->valid_voice ($contact->{voice})) {
		$Error = "Bad phone number $contact->{voice} should be +NNN.NNNNNNNNNN";
		return undef;
	}
	my $frame = $self->_prepare_create_contact_frame($contact);

	# Extensions
	my @spec = $self->spec ('contact-nom-ext');
	my $obj  = $frame->addObject (@spec);
	for my $field (qw/ trad-name type co-no opt-out /) {
		next unless ($contact->{$field});
		my $name = $frame->createElement("contact-nom-ext:$field");
		$name->appendText ($contact->{$field});
		$obj->appendChild ($name);
	}
	my $extension = $frame->command->new ('extension');
	$extension->appendChild ($obj);
	$frame->command->insertAfter ($extension, $frame->getCommandNode);

	my $response = $self->_send_frame ($frame);
	return $Code == 1000 ? 1 : undef;
}

=head2 Register nameservers

To register a nameserver:

	my $host = {
		name   => "ns1.foo.co.uk",
		addrs  => [
			{ ip => '10.2.2.1', version => 'v4' },
		],
	};
	my ($res) = $epp->create_host ($host);

It returns undef on failure or 1 on success.

=cut

# Only need this to set $Code, which is rather annoying.
sub create_host {
	my ($self, $host) = @_;
	my $frame = $self->_prepare_create_host_frame($host);
	return defined $self->_send_frame ($frame);
}

sub _add_nsname {
	my ($self, $name, $frame, $fqdn) = @_;
	my $nsname = $frame->createElement ('domain:hostObj');
	$nsname->appendText ($fqdn);
	$name->appendChild ($nsname);
	return;
}

sub _add_nsaddr {
	my ($self, $name, $frame, $addr) = @_;
	my $nsaddr = $frame->createElement ('host:addr');
	$nsaddr->setAttribute ('ip', $addr->{version});
	$nsaddr->appendText ($addr->{ip});
	$name->appendChild ($nsaddr);
	return;
}

=head1 Modify objects

The domains, contacts and hosts once created can be modified using
these methods.

=head2 Modify domains

To modify a domain, you will need to create a hashref of the
changes like this:

	my $changes = {
		'name'         => 'foo.co.uk',
		'add'          => { ns => ['ns1.newhost.com', 'ns2.newhost.com'] },
		'rem'          => { ns => ['ns1.oldhost.net', 'ns2.oldhost.net'] },
		'chg'          => {},
		'first-bill'   => 'th',
		'recur-bill'   => 'th',
		'auto-bill'    => 21,
		'auto-period'  => 5,
		'next-bill'    => '',
		'notes'        => ['A first note', 'The second note']
	};
	my $res = $epp->update_domain ($changes) or die $epp->get_reason;

This example adds and removes nameservers using the C<add> and C<rem> groups.
You cannot use C<chg> to change nameservers or extension fields. The C<chg>
entry is only used to move a domain between registrants with the same
name.

The extension fields can only be set outside of the add, rem and chg
fields. The supported extensions in this module are:
first-bill, recur-bill, auto-bill, auto-period, next-bill, next-period
and notes. All of these are scalars aside from notes which is an array
ref.

C<update_domain()> returns undef on failure, 1 on success.

There is also a convenience method C<modify_domain()> which takes the
domain name as the first argument and the hashref of changes as the
second argument.

=cut

sub update_domain {
	my ($self, $data) = @_;
	return $self->modify_domain ($data->{name}, $data);
}

sub modify_domain {
	my ($self, $domain, $data) = @_;

	# Sort out the domain to be updated
	my $frame;
	my @spec = $self->spec ('domain');
	$frame = Net::EPP::Frame::Command::Update->new;
	my $obj  = $frame->addObject (@spec);
	my $name = $frame->createElement ('domain:name');
	$name->appendText ($domain);
	$obj->appendChild ($name);

	#Add nameservers as applicable
	my @hostspec = $self->spec ('host');

	for my $action ('add', 'rem', 'chg') {
		if ($data->{$action}) {
			$name = $frame->createElement ("domain:$action");
			if ($data->{$action}->{ns}) {
				my $name2 = $frame->createElement ("domain:ns");
				for my $ns (@{$data->{$action}->{ns}}) {
					$self->_add_nsname ($name2, $frame, $ns);
				}
				$name->appendChild ($name2);
			}
			$obj->appendChild ($name);
		}
	}
	$frame->getCommandNode->appendChild ($obj);

	# Extensions
	@spec = $self->spec ('domain-nom-ext');
	$obj  = $frame->addObject (@spec);
	for my $field (qw/ first-bill recur-bill auto-bill auto-period
			next-bill next-period reseller /) {
		next unless ($data->{$field});
		my $name = $frame->createElement("domain-nom-ext:$field");
		$name->appendText ($data->{$field});
		$obj->appendChild ($name);
	}
	if ($data->{notes}) {
		for my $field (@{$data->{notes}}) {
			my $name = $frame->createElement("domain-nom-ext:notes");
			$name->appendText ($field);
			$obj->appendChild ($name);
		}
	}
	my $extension = $frame->command->new ('extension');
	$extension->appendChild ($obj);
	$frame->command->insertAfter ($extension, $frame->getCommandNode);

	my $response = $self->_send_frame ($frame);
	return $Code == 1000 ? 1 : undef;
}


=head2 Modify contacts

To modify a contact, which includes aspects of the registrant such as
the WHOIS opt-out etc., you will again need to create a hashref of the
changes like this:

	my $changes = {
		'id'          =>  'ABC123',
		'type'        =>  'FCORP',
		'trad-name'   =>  'American Industries',
		'co-no'       =>  '99998888',
		'opt-out'     =>  'N',
		'postalInfo'  => {
			'loc' => {
				'name' => 'James Johnston',
				'addr' => {
					'street'  => ['7500 Test Plaza', 'Testingburg'],
					'city'    => 'Testsville',
					'sp'      => 'Testifornia',
					'pc'      => '99999',
					'cc'      => 'US',
				}
			}
		},
		'voice'	=>	'+1.77777776666',
		'email'	=>	'jj@example.com'
	};
	my $res = $epp->update_contact ($changes) or die $epp->get_reason;

Note that this differs from the syntax of C<Net::EPP::Simple> where that
takes the stock C<add>, C<rem> and C<chg> elements.

It returns undef on failure, 1 on success.

There is also a convenience method C<modify_contact()> which takes the
contact id as the first argument and the hashref of changes as the
second argument.

=cut

sub update_contact {
	my ($self, $data) = @_;
	return $self->modify_contact ($data->{id}, $data);
}

sub modify_contact {
	my ($self, $cont, $data) = @_;

	# Sort out the domain to be updated
	my $frame;
	my @spec = $self->spec ('contact');
	$frame = Net::EPP::Frame::Command::Update->new;
	my $obj  = $frame->addObject (@spec);
	my $name = $frame->createElement ('contact:id');
	$name->appendText ($cont);
	$obj->appendChild ($name);
	my $chg = $frame->createElement ('contact:chg');

	# Ideally we should be able to do this:
	#   $data->{id} ||= $cont;
	#   my $frame = $self->_generate_update_contact_frame($data);
	# but it won't work because of present, but empty, add/rem/chg
	# elements. Equally we cannot do this:
    #   my $frame = Net::EPP::Frame::Command::Update::Contact->new;
	#   $frame->setContact ( $cont );
	# so instead it needs this extra chunk of code which follows:

	# Set contact details
	if (defined $data->{postalInfo}) {
		#Update name and addr
		for my $intloc ('int', 'loc') {
			next unless $data->{postalInfo}->{$intloc};
			my $elem = $frame->createElement ("contact:postalInfo");
			$elem->setAttribute('type', $intloc);
			# Name change?
			my $thisone = $data->{postalInfo}->{$intloc};
			if ($thisone->{name}) {
				my $newname = $frame->createElement ('contact:name');
				$newname->appendText ($thisone->{name});
				$elem->appendChild ($newname);
			}
			if ($thisone->{addr}) {
				my $addr = $frame->createElement ('contact:addr');
				for my $addrbitkey (qw/street city sp pc cc/) {
					next unless defined $thisone->{addr}->{$addrbitkey};
					my $addrbit = $thisone->{addr}->{$addrbitkey};
					if (ref($addrbit) eq 'ARRAY') {
						# Only for street
						for my $street (@$addrbit) {
							my $stbit = $frame->createElement ("contact:$addrbitkey");
							$stbit->appendText ($street);
							$addr->appendChild ($stbit);
						}
					} else {
						my $field = $frame->createElement ("contact:$addrbitkey");
						$field->appendText ($addrbit);
						$addr->appendChild ($field);
					}
				}
				$elem->appendChild($addr);
			}
			$chg->appendChild ($elem);
		}
	}
	if (defined $data->{voice} and not $self->valid_voice ($data->{voice})) {
		$Error = "Bad phone number $data->{voice} should be +NNN.NNNNNNNNNN";
		return undef;
	}
	for my $field ('voice', 'email') {
		next unless defined $data->{$field};
		my $elem = $frame->createElement ("contact:$field");
		$elem->appendText ($data->{$field});
		$chg->appendChild ($elem);
	}
	if ($chg->hasChildNodes) { $obj->appendChild($chg); }

	# Extensions
	@spec = $self->spec ('contact-nom-ext');
	$obj  = $frame->addObject (@spec);
	for my $field (qw/ trad-name type co-no opt-out /) {
		next unless ($data->{$field});
		my $name = $frame->createElement("contact-nom-ext:$field");
		$name->appendText ($data->{$field});
		$obj->appendChild ($name);
	}
	my $extension = $frame->command->new ('extension');
	$extension->appendChild ($obj);
	$frame->command->insertAfter ($extension, $frame->getCommandNode);

	my $response = $self->_send_frame($frame);
	return $Code == 1000 ? 1 : undef;
}

=head2 Modify nameservers

To modify a nameserver, you will need to create a hashref of the
changes like this:

	my $changes = {
		name =>  'ns1.foo.co.uk',
		add  =>  { 'addr' => [ { ip => '192.168.0.51', version => 'v4' } ] },
		rem  =>  { 'addr' => [ { ip => '192.168.0.50', version => 'v4' } ] },
	};
	my $res = $epp->update_host ($changes) or die $epp->get_reason;

This operation can only be used to add and remove ip addresses. The C<chg>
element is not permitted to change addresses, so it is likely that only
the C<add> and C<rem> elements will ever be needed.

It returns undef on failure, 1 on success.

There is also a convenience method C<modify_host()> which takes the
host name as the first argument and the hashref of changes as the
second argument.

=cut

sub update_host {
	my ($self, $data) = @_;
	return $self->modify_host ($self, $data->{name}, $data);
}

sub modify_host {
	my ($self, $host, $data) = @_;

	# Sort out the domain to be updated
	my $frame;
	my @spec = $self->spec ('host');
	$frame = Net::EPP::Frame::Command::Update->new;
	my $obj  = $frame->addObject (@spec);
	my $name = $frame->createElement ('host:name');
	$name->appendText ($host);
	$obj->appendChild ($name);

	for my $action ('add', 'rem', 'chg') {
		if ($data->{$action}) {
			$name = $frame->createElement ("host:$action");
			if ($data->{$action}->{addr}) {
				#my $name2 = $frame->createElement ("host:addr");
				for my $addr (@{$data->{$action}->{addr}}) {
					$self->_add_nsaddr ($name, $frame, $addr);
				}
				#$name->appendChild ($name2);
			}
			$obj->appendChild ($name);
		}
	}

	$frame->getCommandNode->appendChild ($obj);
	my $response = $self->_send_frame ($frame);
	return $Code == 1000 ? 1 : undef;
}

=head1 Querying objects

The interface for querying domains, contacts and hosts is the same as
for L<Net::EPP::Simple> with the addendum that authinfo is not used at
Nominet so can be ignored. The interface is simply:

	my $domhash = $epp->domain_info($domainname);
	my $fulldomhash = $epp->domain_info($domainname, undef, $follow);
	my $conthash = $epp->contact_info ($contid);
	my $hosthash = $epp->host_info ($hostname);

=cut

sub _info {
	my ($self, $type, $identifier) = @_;
	my $frame;
	warn "In _info, type = $type\n" if $Debug;
	if ($type eq 'domain') {
		my @spec = $self->spec ('domain');
		$frame = Net::EPP::Frame::Command::Info->new;
		# The stock frame adds an incorrect domain element  - need it
		# removed or overwritten first
		my $obj  = $frame->addObject (@spec);
		my $name = $frame->createElement ('domain:name');
		$name->appendText ($identifier);
		$obj->appendChild ($name);
		$frame->getCommandNode->appendChild ($obj);
	} elsif ($type eq 'contact') {
		my @spec = $self->spec ($type);
		$frame = Net::EPP::Frame::Command::Info->new;
		my $obj  = $frame->addObject (@spec);
		my $name = $frame->createElement ('contact:id');
		$identifier =~ s/-UK$//;
		$name->appendText ($identifier);
		$obj->appendChild ($name);
		$frame->getCommandNode->appendChild ($obj);
	} elsif ($type eq 'host') {
		$frame = Net::EPP::Frame::Command::Info::Host->new;
		$frame->setHost($identifier);
	} else {
		$Code  = 0;
		$Error = "Unknown object type '$type'";
		return undef;
	}

	my $response = $self->_send_frame ($frame) or return undef;
	my $infData = $response->getNode(($self->spec($type))[1], 'infData');

	if ($type eq 'domain') {
		my $extra = $response->getNode('domain-nom-ext:infData');
		return $self->_domain_infData_to_hash($infData, $extra);
	} elsif ($type eq 'contact') {
		my $this = $self->_contact_infData_to_hash($infData);
		# Strip out the strange empty addr entries created by
		# Net::EPP::Simple
		for my $subtype ('int', 'loc') {
			delete $this->{postalInfo}->{$subtype}->{addr}->{''} if
				$this->{postalInfo}->{$subtype};
		}
		# Add in the Nominet extras (reg, rather than contact)
		my $extra = $response->getNode('contact-nom-ext:infData');
		return $self->_merge_contact_infData ($this, $extra);
	} elsif ($type eq 'host') {
		return $self->_host_infData_to_hash($infData);
	}
}

sub _domain_infData_to_hash {
	my ($self, $infData, $extra) = @_;

	my $hash = $self->_node_to_hash ($infData, ['registrant',
		'clID', 'crID', 'crDate', 'exDate', 'name', 'roid']);

	my $extrahash = $self->_node_to_hash ($extra, ['first-bill',
	'recur-bill', 'auto-bill', 'next-bill', 'auto-period',
	'next-period', 'reg-status', 'notes', 'reseller']);

	for (keys %$extrahash) {
		$hash->{$_} = $extrahash->{$_};
	}

	my $hostObjs = $infData->getElementsByLocalName('hostObj');
	while (my $hostObj = $hostObjs->shift) {
		push(@{$hash->{ns}}, $hostObj->textContent);
	}

	return $hash;
}

sub _merge_contact_infData {
	my ($self, $old, $extra) = @_;

	my $extrahash = $self->_node_to_hash ($extra, ['type',
	'co-no', 'opt-out', 'trad-name']);

	for (keys %$extrahash) {
		$old->{$_} = $extrahash->{$_};
	}
	return $old;

}

sub _node_to_hash {
	my ($self, $node, $namelist) = @_;
	my $hash = {};
	foreach my $child ($node->childNodes) {
		next if $child->nodeType != 1;
		my $tag   = $child->localname;
		my $value = $child->textContent;
		if ($hash->{$tag}) {
			$hash->{$tag} .= "\n$value";
		} else {
			$hash->{$tag} = $value;
		}
	}
	# Not very efficient for a deep copy, but it works.
	if ($namelist) {
		my $temp = {};
		for my $key (@$namelist) {
			$temp->{$key} = $hash->{$key} || '';
		}
		$hash = $temp;
	}
	return $hash;
}

=head1 List Domains

Nominet allows listing domains either by registration date (ie. creation
date) or expiry date. The date must be a month in the form YYYY-MM. eg.

	my $domlist = $epp->list_domains ('2019-01', 'expiry');

will list all the domains expiring in January 2019 as an arrayref. It
will return an empty array ref if there are no matches and undef on
error. The second argument can only be 'expiry' or 'month' (for creation
date). If it is not supplied, the default is 'expiry'.

=cut

sub list_domains {
	my $self = shift;
	my $range = shift;
	my $datetype = shift || 'expiry';
	my $type = 'l';
	my @spec = $self->spec ($type);
	my $frame = Net::EPP::Frame::Command::Info->new;
	my $name = $frame->createElement ('l:list');
	$name->setAttribute ("xmlns:$type", $spec[1]);
	my $child = $frame->createElement ("l:$datetype");
	$child->appendText ($range);
	$name->appendChild ($child);
	$frame->getCommandNode->appendChild ($name);

	my $response = $self->_send_frame($frame) or return undef;
	if ($Code != 1000) { return undef; }

	my $infData = $response->getNode(($self->spec($type))[1], 'listData');
	my $domlist = [];
	for my $node ($infData->childNodes) {
		my $txt = $node->textContent;
		push @$domlist, $txt if $txt =~ /\./;
	}

	return $domlist;
}

=head1 Hello

EPP allows the use of a "hello" operation which effectively tests that
the connection to the EPP server is still active and also serves to
reset any inactivity timeout which the server might apply. Nominet's
documentation seems to indicate a 60 minute timeout (as at August 2013).

	my $res = $epp->hello ();
	
The hello method takes no arguments. It returns 1 on success, undef
otherwise.

This performs much the same function as the ping method of
Net:EPP::Simple (which could be used instead) but provides more
extensive error handling.

=cut

sub hello {
	my $self = shift;
	unless ($self->{connected}) {
		warn "Hello attempt while disconnected\n" if $Debug;
		return undef;
	}
	my $frame = Net::EPP::Frame::Hello->new->toString;

	warn "Sending XML = \n" . $frame . "\n" if $Debug;
	my $greeting = $self->request($frame);
	warn "Response XML = \n" . $greeting->toString() . "\n" if ($Debug
	and defined $greeting);

	unless ($greeting) {
		$Error = sprintf("Server returned a %d code", $Code);
		return undef;
	}
	# greeting returned. Interested in details?
	return 1;
}

=head1 Utility methods

The following utility methods are used internally but are described
here in case they are useful for other purposes.

=head2 spec

This utility method takes a 'type' argument and returns a three-valued
array of type, XMLNS and XSI for use with various frame and XML
routines. It is not expected to be called independently by the user but
is here if you need it.

Type can currently be one of: domain, contact, contact-ext,
host, l (for list), u (for unrenew), r (for release)

	my @spec = $epp->spec ('domain');

=cut

sub spec {
	my ($self, $type) = @_;

	return '' unless $type;

	if ($type eq 'domain') {
		return ($type,
			"urn:ietf:params:xml:ns:domain-$EPPVer",
			"urn:ietf:params:xml:ns:domain-$EPPVer domain-$EPPVer.xsd");
	}
	if ($type eq 'domain-ext' or $type eq 'domain-nom-ext') {
		return ($type,
			'http://www.nominet.org.uk/epp/xml/domain-nom-ext-1.2',
			'http://www.nominet.org.uk/epp/xml/domain-nom-ext-1.2 domain-nom-ext-1.2.xsd');
	}
	if ($type eq 'contact') {
		return ($type,
			"urn:ietf:params:xml:ns:contact-$EPPVer",
			"urn:ietf:params:xml:ns:contact-$EPPVer contact-$EPPVer.xsd");
	}
	if ($type eq 'contact-ext' or $type eq 'contact-nom-ext') {
		return ($type,
			'http://www.nominet.org.uk/epp/xml/contact-nom-ext-1.0',
			'http://www.nominet.org.uk/epp/xml/contact-nom-ext-1.0 contact-nom-ext-1.0.xsd');
	}
	if ($type eq 'host') {
		return ($type,
			"urn:ietf:params:xml:ns:host-$EPPVer",
			"urn:ietf:params:xml:ns:host-$EPPVer host-$EPPVer.xsd");
	}
	if ($type eq 'l') {
		return ($type,
			"http://www.nominet.org.uk/epp/xml/std-list-1.0",
			"http://www.nominet.org.uk/epp/xml/std-list-1.0 std-list-1.0.xsd");
	}
	if ($type eq 'u') {
		return ($type,
			"http://www.nominet.org.uk/epp/xml/std-unrenew-1.0",
			"http://www.nominet.org.uk/epp/xml/std-unrenew-1.0 std-unrenew-1.0.xsd");
	}
	if ($type eq 'r') {
		return ($type,
			"http://www.nominet.org.uk/epp/xml/std-release-1.0",
			"http://www.nominet.org.uk/epp/xml/std-release-1.0 std-release-1.0.xsd");
	}
}

=head2 valid_voice

The valid_voice method takes one argument which is a
string representing a telephone number and returns 1 if it is a valid
string for the "voice" field of a contact or undef otherwise.

	unless ($epp->valid_voice ($phone)) {
		die "The phone number $phone is not in a valid format.";
	}

=cut

sub valid_voice {
	my $self  = shift;
	my $phone = shift or return undef;
	if ($phone !~ /^\+\d{1,3}\.[0-9x]+$/) {
		$Error = "Bad phone number $phone should be +NNN.NNNNNNNNNN";
		return undef;
	}
	return 1;
}

=head2 random_id

The random_id method takes an integer as its optional argument and
returns a random string suitable for use as an ID. When creating a new
contact an ID must be supplied and it must not be globally unique within
the registry (not just within the TAG). This method is used to generate
one of 26339361174458854765907679379456 possible 16-character IDs,
rendering clashes less likely that winning the Lottery two weeks
running (ie. good enough FAPP).

	my $almost_unique_id = $epp->random_id (16);

The length defaults to 16 if not supplied. RFC 5730 specifies that this
is the maximum length for a contact ID.

=cut

sub random_id {
	# Produce a random 16-character string suitable for use as an object
	# ID string if none provided.
	# RFC 5730 says 16 chars max for contact ID
	my ($self, $len) = @_;
	$len ||= 16;
	my $randstr = '';
	while (length ($randstr) < $len) {
		my $num = int(rand(94)) + 33;
		next if ($num == 38 or $num == 60); # XML chars - could escape, but no need
		$randstr .= chr($num);
	}
	return $randstr;
}

=head1 Accessors

The following accessors may be used to extract diagnostic information
from the EPP object:

	my $code    = $epp->get_code;
	my $error   = $epp->get_error;
	my $msg     = $epp->get_message;
	my $reason  = $epp->get_reason;

The first three of these just provide an OO interface to $Code, $Error
and $Message respectively. The user should use these in preference to
the explicit variable names except in the specific instance of a login
or connection failure when no epp object will be returned.

=cut

sub get_code {
	return $Code;
}

sub get_error {
	return $Error;
}

sub get_message {
	return $Message;
}

sub get_reason {
	my $self = shift;
	return $self->{'_reason'};
}

sub set_reason {
	my ($self, $response, @spec) = @_;
	my $reasonnode = $response->getNode ($spec[1], 'reason');
	my $reason = $reasonnode ? $reasonnode->firstChild->toString () : '';
	$reason .= $response->getElementsByLocalName ('msg')->get_node (1)->firstChild->toString ();
	$self->{'_reason'} = $reason;

	return $self->{'_reason'};
}

sub _send_frame {
	my ($self, $frame) = @_;

	warn "Frame to send = " . $frame->toString . "\n" if $Debug > 1;
	my $response = $self->request($frame);
	unless (defined $response) {
		# Critical error
		$Code   = 0;
		$Error  = "No response from server";
		warn $Error;
		return undef;
	}
	warn "Response = " . $response->toString . "\n" if $Debug > 1;

	$Code = $self->_get_response_code($response);
	if ($Code < 1000 or $Code > 1999) {
		$Error = sprintf("Server returned a %d code", $Code);
		warn $Error if $Debug;
		$Message = $response->msg;
		# Get the actual reason
		my $reason = $response->getElementsByTagName ('reason');
		$self->{'_reason'} = $#$reason >= 0 ? $reason->[0]->firstChild->toString () : undef;
		return undef;
	} else {
		# Clear the error
		$Error = '';
		$Message = '';
		$self->{'_reason'} = undef;
	}
	return $response;
}

=head1 TODO

=over

=item * The poll, fork, handshake, lock, tag list and reseller operations
are not yet supported. Nor is there any DNSSEC facility yet.

=item * Retrieving contact info can generate warnings from the
superclass. Ideally this processing should be done locally (within this
class) to avoid these warnings.

=item * Much more extensive tests should be performed.

=back

=head1 See Also

=over

=item * L<Net::EPP::Simple>

=item * Nominet's L<EPP
Documentation|http://registrars.nominet.org.uk/registration-and-domain-management/registrar-systems/epp>

=item * The EPP RFCs: L<RFC 5730|http://tools.ietf.org/html/rfc5730>, 
L<RFC 5731|http://tools.ietf.org/html/rfc5731>,
L<RFC 5732|http://tools.ietf.org/html/rfc5732> and
L<RFC 5733|http://tools.ietf.org/html/rfc5733>.

=back

=head1 Author

Pete Houston <cpan@openstrike.co.uk>

=head1 Licence

This software is copyright (c) 2013 by Pete Houston. It is released
under the Artistic Licence (version 2) and the
GNU General Public Licence (version 2).

=cut

1;
