# Copyright 2002-2009 Interchange Development Group and others
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.  See the LICENSE file for details.

UserTag  usps-query  Order   service weight
UserTag  usps-query  addAttr
UserTag  usps-query  Version 1.10
UserTag  usps-query  Routine <<EOR

sub {
    my ($service, $weight, $opt) = @_;
    my ($rate, $resp, $xml, $mailtype, @intl, $m_rep, $m_mod);
    my %supported_services = (
			      'EXPRESS'     => 1,
			      'FIRST CLASS' => 1,
			      'PRIORITY'    => 1,
			      'PARCEL'      => 1,
			      'BPM'         => 1,
			      'LIBRARY'     => 1,
			      'MEDIA'       => 1,
			      'GLOBAL EXPRESS GUARANTEED'                              => 1,
			      'GLOBAL EXPRESS GUARANTEED NON-DOCUMENT RECTANGULAR'     => 1,
			      'GLOBAL EXPRESS GUARANTEED NON-DOCUMENT NON-RECTANGULAR' => 1,
			      'USPS GXG ENVELOPES'                                     => 1,
			      'EXPRESS MAIL INTERNATIONAL (EMS)'                       => 1,
			      'EXPRESS MAIL INTERNATIONAL (EMS) FLAT-RATE ENVELOPE'    => 1,
			      'PRIORITY MAIL INTERNATIONAL'                            => 1,
			      'PRIORITY MAIL INTERNATIONAL FLAT-RATE ENVELOPE'         => 1,
			      'PRIORITY MAIL INTERNATIONAL REGULAR FLAT-RATE BOXES'    => 1,
			      'PRIORITY MAIL INTERNATIONAL LARGE FLAT-RATE BOX'        => 1,
			      'PRIORITY MAIL INTERNATIONAL SMALL FLAT-RATE BOX'        => 1,
			      'FIRST CLASS MAIL INTERNATIONAL LARGE ENVELOPE'          => 1,
			      'FIRST CLASS MAIL INTERNATIONAL PACKAGE'                 => 1,
			      'MATTER FOR THE BLIND - ECONOMY MAIL'            => 1,
			      );
    my %package_sizes = (
			 'REGULAR'  => 1,
			 'LARGE'    => 1,
			 'OVERSIZE' => 1,
			 );
    my %mailtypes = (
		     'package'                  => 1,
		     'postcards or aerogrammes' => 1,
		     'matter for the blind'     => 1,
		     'envelope'                 => 1,
		     );

    my $error_msg = 'USPS: ';
    my $origin = $opt->{origin} || $::Variable->{USPS_ORIGIN} || $::Variable->{UPS_ORIGIN};
    my $destination = $opt->{destination} || $::Values->{zip} || $::Variable->{SHIP_DEFAULT_ZIP};
    my $userid = $opt->{userid} || $::Variable->{USPS_ID};
    my $passwd = $opt->{passwd} || $::Variable->{USPS_PASSWORD};
    my $url = $opt->{url} || $::Variable->{USPS_URL} || 'http://Production.ShippingAPIs.com/ShippingAPI.dll';
    my $container = $opt->{container} || $::Variable->{USPS_CONTAINER} || 'None';
    my $machinable = $opt->{machinable} || $::Variable->{USPS_MACHINABLE} || 'False';

    $service = uc $service;
    if (! $supported_services{$service}) {
	$error_msg .= "unknown service type $service.";
	return;
    }

    my $size = uc ($opt->{size} || $::Variable->{USPS_SIZE} || 'REGULAR');
    if (! $package_sizes{$size}) {
	$error_msg .= "unknown package size $size.";
	return;
	}

    if ($service eq 'PARCEL') {
	if ($weight < .375 or $weight > 35) {
	    $machinable = 'False';
	}
    }

    if ($opt->{country}) {
	$mailtype = lc ($opt->{mailtype} || $::Variable->{USPS_MAILTYPE} || 'package');
	unless ($mailtypes{$mailtype}) {
	    $error_msg = "unknown mail type '$mailtype'.";
	    return;
	}
    }

    my $modulo = $opt->{modulo} || $::Variable->{USPS_MODULO};
    if ($modulo and ($modulo < $weight)) {
	$m_rep = int $weight / $modulo;
	$m_mod = $weight % $modulo;
	$weight = $modulo;
    }


RATEQUOTE: {
    my $ounces = int(($weight - int($weight)) * 16);
    $weight = int $weight;
    
    if ($opt->{country}) {
        my %map = (
            q{United Kingdom} => q{Great Britain},
            q{Virgin Islands, British} => q{British Virgin Islands},
            q{Viet Nam} => q{Vietnam},
            q{Tanzania, United Republic Of} => q{Tanzania},
            q{Slovakia} => q{Slovak Republic},
            q{Serbia} => q{Serbia-Montenegro},
            q{Montenegro} => q{Serbia-Montenegro},
            q{Samoa} => q{Western Samoa},
            q{Saint Kitts And Nevis} => q{St. Christopher and Nevis},
            q{Russian Federation} => q{Russia},
            q{Pitcairn} => q{Pitcairn Island},
            q{Moldova, Republic Of} => q{Moldova},
            q{Marshall Islands} => q{Republic of the Marshall Islands},
            q{Macedonia, The Former Yugoslav R} => q{Macedonia, Republic of},
            q{Libyan Arab Jamahiriya} => q{Libya},
            q{Lao People's Democratic Republic} => q{Laos},
            q{Korea, Republic of} => q{South Korea},
            q{Iran, Islamic Republic Of} => q{Iran},
            q{Holy See (Vatican City State)} => q{Vatican City},
            q{Georgia} => q{Georgia, Republic of},
            q{Falkland Islands (Malvinas)} => q{Falkland Islands},
            q{Cote d'Ivoire (Ivory Coast)} => q{Cote d'Ivoire},
            q{Congo, The Democratic Republic O} => q{Democratic Republic of the Congo},
            q{Congo} => q{Congo, Republic of the},
            q{Bosnia And Herzegowina} => q{Bosnia-Herzegovina},
        );

        my $usps_country = $map{ $opt->{country} }
            || $opt->{country};

	$xml = qq{API=IntlRate\&XML=<IntlRateRequest USERID="$userid" PASSWORD="$passwd">};
	$xml .= <<EOXML;
	<Package ID="0">
	    <Pounds>$weight</Pounds>
	    <Ounces>$ounces</Ounces>
	    <MailType>$mailtype</MailType>
	    <Country>$usps_country</Country>
	</Package>
	</IntlRateRequest>
EOXML
    }
    else {
	$xml = qq{API=Rate\&XML=<RateRequest USERID="$userid" PASSWORD="$passwd">};
	$xml .= <<EOXML;
	<Package ID="0">
	    <Service>$service</Service>
	    <ZipOrigination>$origin</ZipOrigination>
	    <ZipDestination>$destination</ZipDestination>
	    <Pounds>$weight</Pounds>
	    <Ounces>$ounces</Ounces>
	    <Container>$container</Container>
	    <Size>$size</Size>
	    <Machinable>$machinable</Machinable>
	</Package>
	</RateRequest>
EOXML
    }

    my $ua = new LWP::UserAgent;
    my $req = new HTTP::Request 'POST', "$url";
    $req->content_type('application/x-www-form-urlencoded');
    $req->content($xml);
    my $response = $ua->request($req);

    $error_msg = 'USPS: ';
    if ($response->is_success) {
	$resp = $response->content;
    } 
    else {
	$error_msg .= 'Error obtaining rate quote from usps.com.';
    }

    if ($resp =~ /<Error>/i) {
	$resp =~ m|<Description>(.+)</Description>|;
	$error_msg .=  $1;
    }
    else {
	if ($opt->{country}) {
	    @intl = split /<Service/, $resp;
	    foreach (@intl) {
		m|<SvcDescription>(.+)</SvcDescription>|;
		$resp = uc $1;
		if ($resp eq $service) {
		    m|<Postage>(.+)</Postage>|;
		    $rate += $1;
		    undef $error_msg;
		    last;
		}
	    }
	}
	else {
	    $resp =~ m|<Postage>(.+)</Postage>|;
	    $rate += $1;
	    undef $error_msg;
	}
    }
}

    if ($m_rep) {
	$rate *= $m_rep; undef $m_rep;
    } 
    if ($m_mod) {
	$weight = $m_mod; undef $m_mod;
	goto RATEQUOTE;
    }

    $::Session->{ship_message} .= " $error_msg" if $error_msg;
    return $rate;
}
EOR

UserTag  usps-query  Documentation <<EOD

=head1 NAME


usps-query tag -- calculate USPS costs via www

=head1 SYNOPSIS

  [usps-query
    service="service name"
    weight="NNN"
    userid="USPS webtools user id"*
    passwd="USPS webtools password"*
    origin="NNNNN"*
    destination="NNNNN"*
    url="applet URL"*
    container="container type"*
    size="package size"*
    machinable="True/False"*
    mailtype="mailing type"*
    country="Country name"*
    modulo="NN"*
  ]
	
=head1 DESCRIPTION

Calculates USPS costs via the WWW using the United States Postal Service Rate
Rate Calculator API. You *MUST* register with USPS in order to use this service.
Visit http://www.usps.com/webtools and follow the link(s) to register. You will
receive a confirmation email upon completing the registration process. You 
*MUST* follow the instructions in this email to obtain access to the production
rate quote server. THIS USERTAG WILL NOT WORK WITH USPS's TEST SERVER.


=head1 PARAMETERS

=head2 Base Parameters (always required):


=over 4

=item service

The USPS service you wish to get a rate quote for. Services currently supported:

    EXPRESS
    FIRST CLASS
    PRIORITY
    PARCEL
    BPM
    LIBRARY
    MEDIA
    GLOBAL EXPRESS GUARANTEED
    GLOBAL EXPRESS GUARANTEED NON-DOCUMENT RECTANGULAR
    GLOBAL EXPRESS GUARANTEED NON-DOCUMENT NON-RECTANGULAR
    USPS GXG ENVELOPES
    EXPRESS MAIL INTERNATIONAL (EMS)
    EXPRESS MAIL INTERNATIONAL (EMS) FLAT-RATE ENVELOPE
    PRIORITY MAIL INTERNATIONAL
    PRIORITY MAIL INTERNATIONAL FLAT-RATE ENVELOPE
    PRIORITY MAIL INTERNATIONAL REGULAR FLAT-RATE BOXES
    PRIORITY MAIL INTERNATIONAL LARGE FLAT-RATE BOX
    PRIORITY MAIL INTERNATIONAL SMALL FLAT-RATE BOX
    FIRST CLASS MAIL INTERNATIONAL LARGE ENVELOPE
    FIRST CLASS MAIL INTERNATIONAL PACKAGE
    MATTER FOR THE BLIND - ECONOMY MAIL


=item weight

The total weight of the items to be mailed/shipped.

=item userid

Your USPS webtools userid, which was obtained by registering.
This will default to $Variable->{USPS_ID}, which is the preferred
way to set this parameter.

=item passwd

Your USPS webtools passwd, which was obtained by registering.
This will default to $Variable->{USPS_PASSWORD}, which is the 
preferred way to set this parameter.

=back

=head2 Extended Parameters (domestic and international services)


=over 4

=item url

The URL of the USPS rate quote API. The default is $Variable->{USPS_URL}
or 'http://Production.ShippingAPIs.com/ShippingAPI.dll'.

=item modulo

Enables a rudimentary method of obtaining rate quotes for multi-box shipments. 
'modulo' is a number which represents the maximum weight per box; the default 
is $Variable->{USPS_MODULO}. When modulo > 0, the shipping weight will be divided 
into the number of individual parcels of max. weight 'modulo' which will accommodate 
the whole shipment, and the total rate will be calculated accordingly. 
Example: with modulo = 10, a 34.5lbs. shipment will be calculated as 3 parcels 
weighing 10lbs. each, plus one parcel weighing 4lbs. 8oz.

=back

=head2 Extended Parameters for domestic (U.S.) services only


=over 4

=item origin

Origin zip code. Default is $Variable->{USPS_ORIGIN} or $Variable->{UPS_ORIGIN}.

=item destination

Destination zip code. Default is $Values->{zip} or $Variable->{SHIP_DEFAULT_ZIP}.

=item container

The USPS-defined container type for the shipment. Default is
Variable->{USPS_CONTAINER} or 'None". Please see the Technical Guide to the
Domestic Rates Calculator Application Programming Interface for a complete
list of container types.

=item size

The USPS-defined package size for the shipment. Valid choices are
'REGULAR', 'LARGE', and 'OVERSIZE'. The default is $Variable->{USPS_SIZE} or
'REGULAR'. Please see the Technical Guide to the Domestic Rates Calculator 
Application Programming Interface for a definition of package sizes.

=item machinable (for PARCEL service only)

Possible value are 'True' and 'False'. Indicates whether or not the shipment
qualifies for machine processing by UPS. Default is $Variable->{USPS_MACHINABLE}
or 'False". Consult the USPS service guides for more info on this subject.

=back

=head2 Extended parameters for International services only


=over 4

=item mailtype

The USPS-defined mail type for the shipment. Valid choices are:

    package
    postcards or aerogrammes
    matter for the blind
    envelope

Default is $Variable->{USPS_MAILTYPE} or 'package'. See the USPS international 
service guides for more information on this topic.

=item country (required for international services)

Destination country. No default. You must pass the name of the country, not the ISO
code or abbreviation (i.e. 'Canada', not 'CA'). Note that USPS maintains a table of
valid country names which does not necessarily match all entries in the country
table which is distributed with the standard demo, so modifications may be needed
if you intend to use USPS international services. Consult the USPS International
Services guide for more information.

=back

=head1 BUGS

We shall see....

=head1 AUTHORS

 Ed LaFrance <edl@newmediaems.com>
 Josh Lavin <josh@perusion.com>
 Mathew Jones <mat@bibliopolis.com>

=cut
EOD
