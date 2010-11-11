# Copyright 2002-2010 Interchange Development Group and others
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.  See the LICENSE file for details.

UserTag email Order to subject reply from extra
UserTag email hasEndTag
UserTag email addAttr
UserTag email Interpolate
UserTag email Routine <<EOR

my $Have_mime_lite;
BEGIN {
	eval {
		require MIME::Lite;
		$Have_mime_lite = 1;
	};
}

sub utf8_to_other {
	my ($string, $encoding) = @_;
	return $string unless defined Encode::PERLQQ(); # nop if no Encode

	unless(Encode::is_utf8($string)){
		$string = Encode::decode('utf-8', $string);
	}
	return Encode::encode($encoding, $string);
}

sub {
    my ($to, $subject, $reply, $from, $extra, $opt, $body) = @_;
    my $ok = 0;
    my ($cc, $bcc, @extra, $utf8);

	use vars qw/ $Tag /;

    $subject = '<no subject>' unless defined $subject && $subject;

	if (! $from) {
		$from = $Vend::Cfg->{MailOrderTo};
		$from =~ s/,.*//;
	}

	# Use local copy to avoid mangling with caller's data
	$cc = $opt->{cc};
	$bcc = $opt->{bcc};

	# See if UTF-8 support is required
	$utf8 = $::Variable->{MV_UTF8} || $Global::Variable->{MV_UTF8};

	# Prevent header injections from spammers' hostile content
	for ($to, $subject, $reply, $from, $cc, $bcc) {
		# unfold valid RFC 2822 "2.2.3. Long Header Fields"
		s/\r?\n([ \t]+)/$1/g;
		# now remove any invalid extra lines left over
		s/[\r\n](.*)//s
			and ::logError("Header injection attempted in email tag: %s", $1);
	}

    $reply = '' unless defined $reply;
    $reply = "Reply-to: $reply\n" if $reply;

	for (grep /\S/, split /[\r\n]+/, $extra) {
		# require header conformance with RFC 2822 section 2.2
		push (@extra, $_), next if /^[\x21-\x39\x3b-\x7e]+:[\x00-\x09\x0b\x0c\x0e-\x7f]+$/;
		::logError("Invalid header given to email tag: %s", $_);
	}
	unshift @extra, "From: $from" if $from;

	# force utf8 email through MIME as attachment
	unless (($opt->{attach} || $opt->{html}) && $utf8){
		$opt->{body_mime} = $opt->{mimetype};
		$body = utf8_to_other($body, 'utf-8');
	}	

	my $sent_with_attach = 0;

	ATTACH: {
#::logDebug("Checking for attachment");
		last ATTACH unless $opt->{attach} || $opt->{html};

		unless ($Have_mime_lite) {
			::logError("email tag: attachment without MIME::Lite installed.");
			last ATTACH;
		}

		my $att1_format;
		if($opt->{html}) {
			$opt->{mimetype} ||= 'multipart/alternative';
			$att1_format = 'flowed';
		}
		else {
			$opt->{mimetype} ||= 'multipart/mixed';
		}

		my $att = $opt->{attach};
		my @attach;
		my @extra_headers;

		# encode values if utf8 is supported
		if($utf8){
			$to = utf8_to_other($to, 'MIME-Header');
			$from = utf8_to_other($from, 'MIME-Header');
			$subject = utf8_to_other($subject, 'MIME-Header');
			$cc = utf8_to_other($cc, 'MIME-Header');
			$bcc = utf8_to_other($bcc, 'MIME-Header');
		}

		my $msg = new MIME::Lite 
					To => $to,
					From => $from,
					Subject => $subject,
					Type => $opt->{mimetype},
					Cc => $cc,
					Bcc => $bcc,
				;

		for(@extra) {
			m{(.*?):\s+(.*)};
			my $name = $1 or next;
			next if lc($name) eq 'from';
			my $content = $2 or next;
			$name =~ s/[-_]+/-/g;
			$name =~ s/\b(\w)/\U$1/g;
			$msg->add($name, ($utf8 ? utf8_to_other($content, 'UTF-8')
									: $content)) 
				if $name && $content;
		}

		$opt->{body_mime} ||= 'text/plain' . ($utf8 ? '; charset=UTF-8' : '');
		$opt->{body_encoding} ||= 'quoted-printable';
		$msg->attach(
				Type => $opt->{body_mime},
				Encoding => $opt->{body_encoding},
				Data => $body,
				Disposition => $opt->{body_disposition} || 'inline',
				Format => $opt->{body_format} || $att1_format,
			);

		if(! ref($att) ) {
			my $fn = $att;
			$att = [ { path => $fn } ];
		}
		elsif(ref($att) eq 'HASH') {
			$att = [ $att ];
		}

		$att ||= [];

		if($opt->{html}) {
			unshift @$att, {type => 'text/html' 
							.($utf8 ? '; charset=UTF-8': ''),
							data => ($utf8 ? utf8_to_other($opt->{html}, 'UTF-8') : $opt->{html}),
							disposition => 'inline',
							};
		}

		my %encoding_types = (
			'text/plain' => ($utf8 ? 'quoted-printable' : '8bit'),
			'text/html' => 'quoted-printable',
		);

		for my $ref (@$att) {
			next unless $ref;
			next unless $ref->{path} || $ref->{data};
			unless ($ref->{filename}) {
				my $fn = $ref->{path};
				$fn =~ s:.*[\\/]::;
				$ref->{filename} = $fn;
			}

			$ref->{type} ||= 'AUTO';
			$ref->{disposition} ||= 'attachment';

			if(! $ref->{encoding}) {
				$ref->{encoding} = $encoding_types{$ref->{type}};
			}
			eval {
				$msg->attach(
					Type => $ref->{type},
					Path => $ref->{path},
					Data => $ref->{data},
					Filename => $ref->{filename},
					Encoding => $ref->{encoding},
					Disposition => $ref->{disposition},
				);
			};
			if($@) {
				::logError("email tag: failed to attach %s: %s", $ref->{path}, $@);
				next;
			}
		}

		my $body = $msg->body_as_string;
		my $header = $msg->header_as_string;
#::logDebug("[email] Mail: \n$header\n$body");
		if($opt->{test}) {
			return "$header\n$body";
		}
		else {
			last ATTACH unless $header;
			my @head = split(/\r?\n/,$header);
			$ok = send_mail(\@head,$body);

			$sent_with_attach = 1;
		}
	}

	if ($cc) {
		push(@extra, "Cc: $cc");
	}
	
	if ($bcc) {
		push(@extra, "Bcc: $bcc");
	}

	if ($utf8 && ! $opt->{mimetype}) {
		push(@extra, 'MIME-Version: 1.0');
		push(@extra, 'Content-Type: text/plain; charset=UTF-8');
		push(@extra, 'Content-Transfer-Encoding: 8bit');
	}
	
	$ok = send_mail($to, $subject, $body, $reply, 0, @extra)
			unless $sent_with_attach;

    if (!$ok) {
        logError("Unable to send mail using $Vend::Cfg->{SendMailProgram}\n" .
            "To '$to'\n" .
            "From '$from'\n" .
            "With extra headers '$extra'\n" .
            "With reply-to '$reply'\n" .
            "With subject '$subject'\n" .
            "And body:\n$body");
    }

	return $opt->{hide} ? '' : $ok;
}
EOR

