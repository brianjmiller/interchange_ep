#!/usr/bin/perl

# Interchange::Link -- mod_perl 1.99/2.0 module for linking to Interchange
#
# Copyright (C) 2002-2009 Interchange Development Group
# Copyright (C) 1996-2002 Red Hat, Inc.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package Interchange::Link;


use strict;
use ModPerl::Registry;
use ModPerl::Code;
use Apache2::Const -compile => qw(DECLINED OK NOT_FOUND FORBIDDEN REDIRECT HTTP_MOVED_PERMANENTLY);
use Apache2::ServerRec ();
require Apache2::Connection;
require Apache2::RequestRec;
require Apache2::RequestIO;
require Apache2::RequestUtil;
use Socket;

$ENV{PATH} = "/bin:/usr/bin";
$ENV{IFS} = " ";

## This is what is returned when the environment returns undef
my $global_status;

=head1 NAME

Interchange::Link -- mod_perl 1.99/2.0 module for linking to Interchange

=head1 VERSION

2009-08-22

=head1 SYNOPSIS

  <Location /foundation>
    SetHandler perl-script
     PerlResponseHandler  Interchange::Link
     PerlOptions +GlobalRequest
     PerlSetVar InterchangeServer /var/run/interchange/socket
     PerlSetVar OrdinaryFileList "/foundation/images/ /foundation/dl/"
  </Location>

=head1 DESCRIPTION

Interchange::Link is designed to replace the vlink and tlink programs
that come with Interchange. The Interchange link protocol has been
implemented via an Apache mod_perl modules which saves us the (small) overhead
of the execution of a CGI program.

In addition, it will deliver downloadable files in a streaming fashion
without keeping Interchange open, which cuts overhead dramatically for
large downloadable files. See L<FileDeliveryBase>.

Note that this module is not compatible with Apache 1.

=head1 PREREQUISITES

You must have mod_perl 1.99 or higher installed on your Apache. On a
Red Hat-style Linux system, it is as simple as:

    rpm -i mod_perl-1.99.XX-X.rpm
    service httpd restart

Installation of mod_perl will vary from system to system. Consult the
mod_perl documentation. Sometimes it is as easy as

    perl -MCPAN -e 'install ModPerl::Registry'

but often it is not.

Usually you can download the package from http://perl.apache.org/ and
follow those instructions.

=head1 INSTALLATION

You must specify that Apache use mod_perl, and you must tell it where
to find the Perl modules you want to use. 

On a Red Hat Linux system you might copy this file to /usr/lib/httpd/perl/
via this procedure:

    mkdir -p /usr/lib/httpd/perl/Interchange
    cp Link.pm /usr/lib/httpd/perl/Interchange

If you have mod_perl2 1.999_21 or earlier, you should instead do:

    mkdir -p /usr/lib/httpd/perl/Interchange
    cp Link.pm.mod_perl-1.999_21_and_before /usr/lib/httpd/perl/Interchange

Then you provide a startup script that tells mod_perl where its
libraries are:

    cd /usr/lib/httpd/perl
    echo "use lib qw(/usr/lib/httpd/perl);1;" > startup.pl

Then you can put in your /etc/httpd/conf/httpd.conf:

    PerlModule Apache2
    PerlRequire /usr/lib/httpd/perl/startup.pl

Finally, you specify a location like:

  <Location /foundation>
    SetHandler perl-script
     PerlResponseHandler  Interchange::Link
     PerlOptions +GlobalRequest
	 # Make sure you set SocketPerms to 0666 (or 0660 with appropriate
	 # setgid group ownership of the directory)
     PerlSetVar InterchangeServer /var/run/interchange/socket
     PerlSetVar OrdinaryFileList "/foundation/images/ /foundation/dl/"
  </Location>

Note: The Apache <Location> path should not contain a dot (.) or any
other characters except A-Z, a-z, 0-9 or a hyphen (-), so:

    <Location /shop.name> is invalid, whereas:
    <Location /shop-name> is valid.

The specifics of the configuration are discussed in the next section.

=head1 CONFIGURATION

The module understands directives set via the mod_perl C<PerlSetVar>
directive. 

=over 4

=item InterchangeServer 

This specifies the way to contact the
primary and possibly additionial Interchange servers. The InterchangeServer
directive takes either a pathname to the Interchange UNIX socket or a
host:port specification if you want to use INET mode.

Normally this takes the form of:

     PerlSetVar InterchangeServer /var/run/interchange/socket

Note that your file permissions for the socket file need to allow the
Apache User uid to read and write it. This usually means "SocketPerms
0666" or in interchange.cfg.  You can also do "SocketPerms 0660" if you
set the group of the containing directory to the Apache Group value,
and change the directory permissions to enable the setgid bit. (That is
accomplished with "chmod g+s <directory>".)

If you want to specify more than one so that a backup server can provide
request support in case of failure:

    PerlSetVar InterchangeServer  "/var/run/interchange/socket 10.1.1.1:7786"

The optional InterchangeServerBackup directive takes the same arguments,
but should obviously point to a different Interchange server than the
primary.  The InterchangeServerBackup directive is only of any use if
you have multiple Interchange servers configured in a clustered environment.

If you want to randomly select from a series of clustered servers, do:

    PerlSetVar InterchangeServer "10.1.1.1:7786 10.1.1.2:7786 10.1.1.3:7786"
    PerlSetVar RandomServer 1

Note: The Apache <Location> path should not contain a dot (.) or any
other characters except A-Z, a-z, 0-9 or a hyphen (-), so:

    <Location /shop.name> is invalid, whereas:
    <Location /shop-name> is valid.

Example of a UNIX mode local connection:

    <Location /shop>
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar InterchangeServer /opt/interchange/etc/socket
    </Location>

Example of INET mode local connection:

    <Location /shop>
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar InterchangeServer localhost:7786
    </Location>

UNIX mode local primary connection and INET mode remote backup connection:

    <Location /shop>
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar InterchangeServer /opt/interchange/etc/socket
    PerlSetVar InterchangeServerBackup another.server.com:7786
    </Location>

The default if not set is C<127.0.0.1:7786>.

=item ConnectTries and ConnectRetryDelay

The ConnectTries parameter specifies the number of connection attempts to
make before giving up.  ConnectRetryDelay specifies the delay, in seconds,
between each retry attempt.

The ConnectTries default is 10 and the ConnectRetryDelay default is 2 seconds.
Here is an example:

    <Location /shop>
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar ConnectTries 10
    PerlSetVar ConnectRetryDelay 1
    </Location>

=item DropRequestList

The DropRequestList allows a list of space-separated URI components
to be specified.  If one of the list entries is found anywhere in the
requested URI, the request will be dropped with a 404 (not found) error,
without the request being passed to Interchange.  This parameter is useful
for blocking known Microsoft IIS attacks like "Code Red", so that we don't
waste any more time processing the (bogus) requests than we have to.

    <Location /shop>
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar DropRequestList "/default.ida /x.ida /cmd.exe /root.exe"
    </Location>

=item OrdinaryFileList 

The OrdinaryFileList allows a list of space-separated URI path
components to be specified.  If one of the list entries is found at the
start of any request then that request will not be passed to Interchange.
Instead, the file will be directly served by Apache.  For example:

    <Location />
    SetHandler perl-script
    PerlResponseHandler Interchange::Link
    PerlSetVar OrdinaryFileList "/foundation/ /interchange-5/ /robots.txt"
    </Location>

This will result in the following:

    www.example.com/index.html          (handled by Interchange)
    www.example.com/ord/basket.html     (handled by Interchange)
    www.example.com/foundation/images/somefile.gif (served by Apache)
    www.example.com/robots.txt          (served by Apache)

You should add a trailing slash to directory names to prevent, for instance,
"/images/foo.gif" from being confused with the likes of "/images.html".
If OrdinaryFileList was set to "/images" then both of those requests would
be handled by Apache.  If OrdinaryFileList was set to "/images/" then
"/images/foo.gif" would be handled by Apache and "/images.html" would be
handled by Interchange.

If you're using "<Location />" then you will need a dummy "index.html" file
in your VirtualHost's DocumentRoot directory to avoid permission problems
assocated with the Apache directory index creation code.

=item InterchangeScript

The InterchangeScript parameter allows the SCRIPT_NAME to be different from
the <Location>.  For example:

    <Location /shop>
        ...
    </Location>

The above will set the SCRIPT_NAME to "/shop".

    <Location /shop>
        ...
    PerlSetVar InterchangeScript /foo
    </Location>

The above will set the SCRIPT_NAME to "/foo", instead of "/shop"  before
passing the request to Interchange.

The appropriate SCRIPT_NAME must be configured into the "Catalog"
directive in your interchange.cfg file.

=item FileDeliveryBase

Interchange::Link can deliver files without needing to keep Interchange
open. To do this, you set the HTTP Status: header to C<httpd_deliver>.
In Interchange 5.0 or higher you can do this by putting in a page:

    [deliver
        status=httpd_deliver
        location=directory/file.ext
        type=application/octet-stream
       ]

The C<FileDeliveryBase> setting determines where the file will be
relative to. While you can set it to C</>, that is not recommended
as files like C</etc/passwd> could be delivered.

The default is the document root of the Apache server. To protect
files from being served directly by Apache, you can either put them
under a directory at the Interchange location, or you can use normal
Apache exclusions.

=item NoBlankLines

Set C<NoBlankLines> to 1 to remove blank lines from the outputted source
code.

=back

=head1 BUGS

Send bug reports and suggestions to the Interchange users list,
<interchange-users@icdevgroup.org>.

=head1 COPYRIGHT AND LICENSE

 Copyright (C) 2002-2009 Interchange Development Group
 Copyright (C) 1996-2002 Red Hat, Inc.

This program is free software.  You can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation.  You may refer to either version 2 of the
License or (at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
for more details.

=cut

my %config;

sub setup_location {
    my $r = shift;
    my $s = $r->server;
    my $location = $r->location;

    return $config{$location} if $config{$location} && !($s->is_virtual());

#warn "Getting location $location\n";

    my $c = $config{$location} = {};

    $c->{InterchangeScript} = $r->dir_config('InterchangeScript') || $location;

    my @OrdinaryFileList;
    ORDINARY: {
        my $ordstring = $r->dir_config('OrdinaryFileList')
            or last ORDINARY;
        @OrdinaryFileList = grep /\S/, split /\s+/, $ordstring;
        for (@OrdinaryFileList) {
            $_ = qr(^$_);
        }
    }

    my @DropRequestList;
    DROPREQ: {
        my $dropstring = $r->dir_config('DropRequestList')
            or last DROPREQ;
        @DropRequestList = grep /\S/, split /\s+/, $dropstring;
        for (@DropRequestList) {
            $_ = qr(^$_$);
        }
    }

    SERVPOOL: {
        my $serverpool = $r->dir_config('ServerPool');
        if(! $serverpool) {
            $serverpool = $r->dir_config('InterchangeServer');
            if($serverpool and $r->dir_config('InterchangeServerBackup')) {
                $serverpool .= " " . $r->dir_config('InterchangeServerBackup');
            }
        }

        $serverpool ||= '127.0.0.1:7786';
        $serverpool =~ s/^\s+//;
        $serverpool =~ s/\s+$//;

        my @servpool = split /\s+/, $serverpool;
        $c->{ServerPool} = \@servpool;
    }

    my $base = $r->dir_config('FileDeliveryBase') || $r->document_root;
	$base =~ s:/*$:/: unless $base eq '/';
	
	$c->{FileDeliveryBase} = $base;

    $c->{RandomServer} = $r->dir_config('RandomServer');

    $c->{ConnectTries} = $r->dir_config('ConnectTries') || 10;
    $c->{ConnectRetryDelay} = $r->dir_config('ConnectRetryDelay') || 2;

    $c->{DropRequestList} = \@DropRequestList if @DropRequestList;
    $c->{OrdinaryFileList} = \@OrdinaryFileList if @OrdinaryFileList;

    return $c;
}

my $arg;
my $env;
my $ent;


sub server_not_running {

    my $r = shift;
    my $msg;

    warn "ALERT: Interchange server not running for $ENV{SCRIPT_NAME}\n";   

    $r->content_type ("text/html");
    $r->print (<<EOF);
<html><head><title>Service unavailable</title></head>
<body>
<p>
We are temporarily out of service or may be experiencing high system demand.
Please try again soon.
</p>
</body>
</html>
EOF
# use for debugging:
#$arg
#$env
#$ent

}

# Read the entity from stdin if present.

sub send_arguments {

    my $count = @ARGV;
    my $val = "arg $count\n";
    for(@ARGV) {
        $val .= length($_);
        $val .= " $_\n";
    }
    return $val;
}

sub send_environment {
    my $r = shift;
    my $c = $r->connection;

#warn("Connection=$c");

    my ($str);
    my $val = '';
    my $count = 0;

    my $uri = $r->uri;
#warn "uri=$uri\n";

    my $location = $r->location;
    my $cfg = setup_location($r);

    if(my $ord = $cfg->{OrdinaryFileList}) {
        for(@$ord) {
#warn "checking for OrdinaryFile $_\n";
            next unless $uri =~ $_;
            $global_status = Apache2::Const::DECLINED;
            return undef;
        }
    }

    if(my $drop = $cfg->{DropRequestList}) {
        for(@$drop) {
#warn "checking for DropRequest $_\n";
            next unless $uri =~ $_;
            $r->headers_out->{Status} = '404 Not found';
            $r->content_type('text/html');
#warn "dropping request for $uri\n";
            $global_status = Apache2::Const::NOT_FOUND;
            return undef;
        }
    }

    my $method = $r->method;
#warn "method=$method\n";

    $uri =~ s{^$location}{} unless $location eq '/';

    my $query = $r->args;

    my $script = $cfg->{InterchangeScript};

    my %header_map = qw/
        AUTHORIZATION_TYPE   AUTH_TYPE
        AUTHORIZATION        AUTHORIZATION
        COOKIE               HTTP_COOKIE
        CLIENT_HOSTNAME      REMOTE_HOST
        CLIENT_IP_ADDRESS    REMOTE_ADDR
        CLIENT_IDENT         REMOTE_IDENT
        CONTENT_LENGTH       CONTENT_LENGTH
        CONTENT_TYPE         CONTENT_TYPE
        COOKIE               HTTP_COOKIE
        FROM                 HTTP_FROM
        HOST                 HTTP_HOST
        HTTPS_ON             HTTPS
        METHOD               REQUEST_METHOD
        PATH_INFO            PATH_INFO
        PATH_TRANSLATED      PATH_TRANSLATED
        PRAGMA               HTTP_PRAGMA
        QUERY                QUERY_STRING
        RECONFIGURE          RECONFIGURE_MINIVEND
        REFERER              HTTP_REFERER
        SCRIPT               SCRIPT_NAME
        SERVER_HOST          SERVER_NAME
        SERVER_PORT          SERVER_PORT
        USER_AGENT           HTTP_USER_AGENT
        CONTENT_ENCODING     HTTP_CONTENT_ENCODING
        CONTENT_LANGUAGE     HTTP_CONTENT_LANGUAGE
        CONTENT_TRANSFER_ENCODING HTTP_CONTENT_TRANSFER_ENCODING
    /;

    my %header;
    for(keys %{$r->headers_in}) {
        my $val = $r->headers_in->{$_};
        my $k = uc $_;
        $k =~ s/-/_/g;
        $k = $header_map{$k} || "HTTP_$k";
        $header{$k} = $val;
#warn "header $_/$k=$val\n";
    }

    my @pairs = (
        SCRIPT_NAME    => $script,
        REQUEST_METHOD => $r->method,
        PATH_INFO       => $uri,
        MOD_PERL        => 1,
        QUERY_STRING    => $query,
        REMOTE_ADDR     => $c->remote_ip,
        %header,
        %ENV,
    );

    my %seen;

    while (@pairs) {
        my $n = shift @pairs;
        my $v = shift @pairs;
        next if $seen{$n}++;

        $count++;
        $str = "$n=$v";
        $val .= length($str);
        $val .= " $str\n";
    }
    $val = "env $count\n$val";
    return $val;
}

sub check_entity {
    my $r = shift;
    my $len = $r->headers_in->{'Content-Length'};
    return '' unless $len > 0;
    return "entity\n$len ";
}

sub shuffle {
    my $array = shift;
    my $i;
    for ($i = @$array; --$i; ) {
        my $j = int rand ($i+1);
        next if $i == $j;
        @$array[$i,$j] = @$array[$j,$i];
    }
}

sub handler {
    my $r = shift;
#warn "current location=" . $r->location . "\n";

    my $uri = $r->uri;
#warn "Entering handler.\n";
    $arg = send_arguments($r);
#warn "Got arguments.\n";
    $env = send_environment($r)
        or return $global_status;
#warn "Got environment.\n";
    $ent = check_entity($r);
#warn "Got entity.\n";

    my $cfg = setup_location($r);

    $SIG{PIPE} = 'IGNORE';
    $SIG{ALRM} = sub { server_not_running($r); exit 1; };

    my ($remote, $port, $iaddr, $paddr, $proto, $line);

    my $ok;

    local(*SOCK);

    my $socklist = $cfg->{ServerPool};

    if($cfg->{RandomServer}) {
        $socklist = [ @$socklist ];
        shuffle($socklist);
    }

    my $tries = 0;
    while ($tries++ < $cfg->{ConnectTries}) {
        for my $sockname (@$socklist) {
#warn "InterchangeServer=$sockname\n";
            if($sockname =~ m{/}) {
                socket(SOCK, PF_UNIX, SOCK_STREAM, 0)   or die "socket: $!\n";
                $paddr = sockaddr_un($sockname);
#warn "vlink $sockname RandomServer=$cfg->{RandomServer}\n";
            }
            else {
                ($remote, $port) = split /:/, $sockname, 2;
#warn "tlink remote=$remote port=$port RandomServer=$cfg->{RandomServer}\n";
                $port ||= 7786;

                if ($port =~ /\D/) { $port = getservbyname($port, 'tcp'); }

                $iaddr = inet_aton($remote);
                $paddr = sockaddr_in($port,$iaddr);

                $proto = getprotobyname('tcp');

                socket(SOCK, PF_INET, SOCK_STREAM, $proto)  or die "socket: $!\n";
            }


        #warn "Ready to connect.\n";
            do {
               $ok = connect(SOCK, $paddr);
            } while ( ! defined $ok and $! =~ /interrupt/i);

            my $def = defined $ok;
            warn "ok=$ok defined=$def sockname=$sockname: $!\n" if ! $ok;
            next unless $ok;
            last;
    #warn "Connected.\n";
        }
        last if $ok;
        sleep($cfg->{ConnectRetryDelay});
    }

    $ok   or do {
                    server_not_running($r);
                    return Apache2::Const::OK;
            };

    my $former = select SOCK;
    $| = 1;
    select $former;

    alarm 0;

    print SOCK $arg;
    print SOCK $env;
    if($ent) {
#warn "there is an entity=$ent";
        print SOCK $ent;
        while(<>) {
            print SOCK $_;
        }
        print SOCK "\n";
    }

    print SOCK "end\n";

    my @out;
    my @header;
#warn "reading from SOCK\n";
    while( <SOCK> ) {
#warn "GOT header read from SOCK: $_\n";
        last unless /\S/;
        push @header, $_;
    }

    my $set_status;
    my $set_content;
    my $deliver_object;

    for(@header) {
        next unless /^[-\w]+:/;
        s/\s+$//;
        my ($k, $v) = split /:\s*/, $_, 2;
        my $lc = lc $k;
        if($lc eq 'content-type') {
            $set_content = $v;
            next;
        }
        elsif($lc eq 'status') {
            $set_status = $v;
        }
		elsif($lc eq 'mod-perl-deliver') {
			$deliver_object = $v;
		}
#warn "Setting header=$k to '$v'\n";
        $r->headers_out->{$k} = $v;
    }

    $set_content ||= 'text/html';

    if($set_status) {
        if($set_status =~ /^30[21]/) {
#warn "Doing redirect\n";
            $r->content_type($set_content);
            close (SOCK)                                or die "close: $!\n";
            return Apache2::Const::HTTP_MOVED_PERMANENTLY if $set_status == 301;
            return Apache2::Const::REDIRECT;
        }
        elsif($set_status =~ /^404/) {
#warn "404 not found status\n";
            close (SOCK)                                or die "close: $!\n";
            return Apache2::Const::NOT_FOUND;
        }
		elsif($set_status eq 'httpd_deliver') {
			$deliver_object = $set_status;
		}
    }

	if($deliver_object) {
		my $fn = $r->headers_out->{Location}
			or die "No location for delivery.\n";

		$fn =~ s:^/*:$cfg->{FileDeliveryBase}:;

		close SOCK                                or die "close: $!\n";
		unless (open IN, "< $fn") {
			warn "cannot open mod_perl_deliver $fn: $!\n";
			$r->content_type('text/html');
			if(! -e $fn) {
				$r->headers_out->{Status} = '404 Not found';
				return Apache2::Const::NOT_FOUND;
			}
			else {
				$r->headers_out->{Status} = '403 Permission denied';
				return Apache2::Const::FORBIDDEN;
			}
		}

		$r->headers_out->{Status} = '200 OK';
		$r->headers_out->{'Content-Length'} = -s $fn;
		$r->content_type($set_content);

		while(<IN>) {
			print
				or die "recipient write for $deliver_object failed: $!\n";
		}
		close IN
			or die "cannot close $deliver_object: $!\n";
	}
	else {

		$r->content_type($set_content);
		my $no_blank_lines = $r->dir_config('NoBlankLines');
		while (<SOCK>) {
			push @out, $_ unless $no_blank_lines and ! /\S/;
		}
		close (SOCK)                                or die "close: $!\n";
		print @out;
	}

#warn "Returning OK\n";
    return Apache2::Const::OK;
}

1;
