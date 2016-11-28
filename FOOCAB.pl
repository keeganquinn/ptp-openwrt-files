#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use NetAddr::IP::Lite;
use LWP::Simple;
use JSON qw( decode_json );
use Data::Dumper;

my $DEBUG = 1;

# IPv6 prefix - this one belongs to PTP
my $iPV6SLASH48 = "2001:470:8307";

my $host;
my $node;

my $APINODEBASE = "https://personaltelco.net/api/v0/nodes/";
my $APIHOSTBASE = "https://personaltelco.net/api/v0/hosts/";
my $IMGBASE = "https://personaltelco.net/splash/images/nodes/";

my $result = GetOptions(
	"host=s" => \$host,
	"node=s" => \$node
);

my $nodeinfo;

if ( defined( $host )) {
	$nodeinfo = getNodeInfoByHost($host);
	if ( $nodeinfo->{'hostname'} ne $host ) {
		die "did not find host $host from $APIHOSTBASE";
		exit;
	}
	$node = $nodeinfo->{'node'};
} elsif ( defined( $node )) {
	$nodeinfo = getNodeInfoByNode($node);
	if ( $nodeinfo->{'node'} ne $node ) {
		die "did not find node $node from $APINODEBASE";
		exit;
	}
	$host = $nodeinfo->{'hostname'};
} else {
	die "did not specify a node or host, loser!";
	exit;
}

my $vpniface    = "ptp";
my $logo        = $nodeinfo->{'logo'};
my $bridge      = $nodeinfo->{'bridge'};
my $device      = $nodeinfo->{'device'};
my $filter      = $nodeinfo->{'filter'};
my $pubifaces   = $nodeinfo->{'pubifaces'};
my $privifaces  = $nodeinfo->{'privifaces'};
my $waniface    = $nodeinfo->{'waniface'};
my $masklen     = $nodeinfo->{'pubmasklen'};
my $pubaddr     = $nodeinfo->{'pubaddr'};
my $privaddr    = $nodeinfo->{'privaddr'};
my $privmasklen = $nodeinfo->{'privmasklen'};
my $hwclock     = $nodeinfo->{'hwclock'};

sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}
# Left trim function to remove leading whitespace
sub ltrim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	return $string;
}
# Right trim function to remove trailing whitespace
sub rtrim($)
{
	my $string = shift;
	$string =~ s/\s+$//;
	return $string;
}


if ( !defined( $nodeinfo->{'logo'} ) ) {
	$nodeinfo->{'logo'} = "ptp-logo-comm-wire-223x223.png";
}

open( SED, ">foocab.sed" ) or die "can't open foocab.sed: " . $!;
foreach my $k ( keys %$nodeinfo ) {
	my $sed = "s|PTP_" . uc($k) . "_PTP|" . trim($nodeinfo->{$k}) . "|g\n";
	print $sed if $DEBUG;
	print SED $sed;
}

if ( !defined( $nodeinfo->{'dhcpstart'} ) ) {
	$nodeinfo->{'dhcpstart'} = 5;
	print "dhcpstart not found, setting  to " . $nodeinfo->{'dhcpstart'}, "\n";
	my $sed = "s/PTP_DHCPSTART_PTP/" . $nodeinfo->{'dhcpstart'} . "/g\n";
	print $sed if $DEBUG;
	print SED $sed;
}

my @octets = split( /\./, $nodeinfo->{'pubaddr'} );
printf( SED "s/PTP_PUB6PREFIX_PTP/%s:%02x%02x::/g\n",
	$iPV6SLASH48, $octets[2], $octets[3] );
printf( SED "s/PTP_VPN6ADDRESS_PTP/%s::%02x%02x/g\n",
	$iPV6SLASH48, $octets[2], $octets[3] );

print "DEVICE=" . $nodeinfo->{'device'} . "\n";

if ( !defined( $pubifaces )) {
	$pubifaces = "";
}

if ( $device eq "DIR860L" || $device eq "WDR3600" || $device eq "WGT634U" ) {
	$waniface = "eth0.2";
	if ($bridge) {
		$pubifaces  = "eth0.1";
	} else {
		$privifaces = "eth0.1";
	}
} elsif ( $device eq "ALIX" || $device eq "APU") {
	$waniface = "eth0";
	if ($bridge) {
		$pubifaces  = "eth1 eth2";
	} else {
		$pubifaces  = "eth1";
		$privifaces = "eth2";
	}
	$hwclock = 1;
} elsif ( $device eq "NET4521" ) {
	$waniface = "eth0";
	if ($bridge) {
		$pubifaces  = "eth1";
	}
	else {
		$privifaces = "eth1";
	}
	$hwclock = 1;
} elsif ( $device eq "NET4826" ) {
	$waniface   = "eth0";
	$hwclock = 1;
} elsif ( $device eq "MR3201A" ) {
	$waniface   = "eth0";
} elsif ( $device eq "RSTA" ) {
	$waniface = "eth0";
	if ($bridge) {
		$pubifaces = "eth1";
	}
	else {
		$privifaces = "eth1";
	}
} elsif ( $device eq "WNDR3800" ) {
	$waniface = "eth1";
	if ($bridge) {
		$pubifaces  = "eth0";
	} else {
		$privifaces = "eth0";
	}
} elsif ( $device eq "WZR600DHP" || $device eq "AIRROUTER" ) {
	$waniface = "eth1";
	if ($bridge) {
		$pubifaces  = "eth0";
	} else {
		$privifaces = "eth0";
	}
} elsif ( $device eq "ROCKET" || $device eq "MR24") {
	$waniface = "eth0";
	$pubifaces = "";
}

print SED "s/PTP_WANIFACE_PTP/$waniface/g\n";
print SED "s/PTP_PUBIFACES_PTP/$pubifaces/g\n";

if ( ! defined($masklen) ||  !defined($pubaddr) ) {
  die "Not enough information to compute network! pubaddr: " . $pubaddr . " masklen: " . $masklen ;
}

my $ip      = NetAddr::IP::Lite->new("$pubaddr/$masklen");
my $network = $ip->network();
my $netaddr = $network->addr();
my $mask    = $ip->mask();

print SED "s/PTP_PUBNET_PTP/$netaddr/g\n";
print SED "s/PTP_PUBNETMASK_PTP/$mask/g\n";

if ( $privaddr ) {
	print "privaddr = $privaddr\n";

	$ip      = NetAddr::IP::Lite->new("$privaddr/$privmasklen");
	$network = $ip->network();
	$netaddr = $network->addr();
	$mask    = $ip->mask();

	print SED "s/PTP_PRIVIFACES_PTP/$privifaces/g\n";
	print SED "s/PTP_PRIVNET_PTP/$netaddr/g\n";
	print SED "s/PTP_PRIVNETMASK_PTP/$mask/g\n";
} else {
	print "privifaces not defined\n";
}
close SED;

open( FILES, "find etc lib usr root -type f |" );

while (<FILES>) {
	chomp;
	my $src    = $_;
	my @path   = split( '/', $src );
	my $fname  = pop @path;
	my $outdir = join( '/', "output", @path );
	my $dest   = join( '/', "output", @path, $fname );

	# print "source = $src ; outdir = $outdir ; dest = $dest\n";

	my (
		$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
		$size, $atime, $mtime, $ctime, $blksize, $blocks
	) = stat($src);

	unless ( -d $outdir ) { 
		system("mkdir -p $outdir"); 
	}
    my $cmd = "sed -f foocab.sed < $src > $dest"; 
	print $cmd, "\n";
	system($cmd);

	chmod( $mode, $dest );
	chown( $uid, $gid, $dest );
}

open( LINKS, "find etc usr root -type l |" );

while (<LINKS>) {
	chomp;

	my $src    = $_;
	my @path   = split( '/', $src );
	my $fname  = pop @path;
	my $outdir = join( '/', "output", @path );
	my $dest   = join( '/', "output", @path, $fname );

	unless ( -d $outdir ) { system("mkdir -p $outdir"); }

	print "cp -a $src $dest\n";

	system("cp -a $src $dest");
}

if ( ! $privaddr ) {
	unlink "output/etc/rc.d/S46firewall_private";
	unlink "output/etc/init.d/firewall_private"; 
	unlink "output/etc/uci-defaults/ptp.private.defaults";
}

if ( $filter ne "NONE" ) {
	my $outdir = "output/etc/hotplug.d/iface";

	unless ( -d $outdir ) { system("mkdir -p $outdir"); }

	# create filter script and /etc/rc.d link
	open( FILTER, ">$outdir/60-filter" );

	print FILTER "#!/bin/sh\n\n";

	if ( $filter eq "WAN" || $filter eq "BOTH" ) {
		print FILTER "WANF=/tmp/run/wanfilter.net

[ \"\$INTERFACE\" = \"wan\" ] && {
	[ \"\$ACTION\" = ifup ] && {
		# prevent first-hop WAN destinations from being reached from the public or ptp (vpn) interfaces
		for wannet in \$(ip addr show dev \$DEVICE | grep 'inet ' | awk '{ print \$2 }') ; do 
			echo \$wannet >> \$WANF
			iptables -I FORWARD -i br-pub -d \$wannet -j DROP ; 
			iptables -I FORWARD -i $vpniface -d \$wannet -j DROP ; 
		done
		# not needed for ipv6 because we don't currently provision ipv6 from the upstream network
		# all ipv6 traffic goes via our vpn tunnel, and link-local addresses aren't relevent to 
		# FORWARDing (you don't need to drop link-local traffic at a routing boundary, it's not 
		# forwarded by definition, since it isn't link-local anymore).
	}
	[ \"\$ACTION\" = ifdown ] && {
		if [ -f \$WANF ]; then
			for wannet in \$(cat \$WANF) ; do
				iptables -D FORWARD -i br-pub -d \$wannet -j DROP
				iptables -D FORWARD -i $vpniface -d \$wannet -j DROP
			done
			rm \$WANF
		fi
	}
}\n";
	}

	if ( defined($privaddr) && ( $filter eq "PRIV" || $filter eq "BOTH" ) ) {
		print FILTER "
    
[ \"\$INTERFACE\" = \"priv\" ] && {
	[ \"\$ACTION\" = ifup ] && {
		# prevent PRIV destinations from being reached from the public or ptp (vpn) interfaces
		iptables -I FORWARD -o br-priv -i br-pub -j DROP
		iptables -I FORWARD -o br-priv -i $vpniface -j DROP
	}
	[ \"\$ACTION\" = ifdown ] && {
		iptables -D FORWARD -o br-priv -i br-pub -j DROP
		iptables -D FORWARD -o br-priv -i $vpniface -j DROP
	}
}\n";
	}

	close(FILTER);
}

if ($hwclock) {
	open( INITCLOCK, ">output/etc/init.d/initclock" );

	print INITCLOCK "#!/bin/sh /etc/rc.common
# Copyright (C) 2008 OpenWrt.org

START=11

start() {
	# set clock to hardware clock value
	/sbin/hwclock -s -u
}\n";

	close(INITCLOCK);
	chmod 0755, "output/etc/init.d/initclock";

	open( CRONTAB, ">>output/etc/crontabs/root" );
	print CRONTAB "0 0 * * *	/sbin/hwclock -w -u\n";
	close(CRONTAB);
}

# fetch_image.sh script

my $imagename = "";
if ( $device eq "ALIX" ) {
	$imagename = "x86/geode/lede-x86-geode-combined-squashfs.img";
} elsif ( $device eq "APU" ) {
	$imagename = "x86/64/lede-x86-64-combined-squashfs.img";
} elsif ( $device eq "DIR860L" ) {
	$imagename = "ramips/mt7621/lede-ramips-mt7621-dir-860l-b1-squashfs-sysupgrade.bin";
} elsif ( $device eq "NET4521" || $device eq "NET4826" ) {
	$imagename = "x86/legacy/lede-x86-legacy-combined-squashfs.img";
} elsif ( $device eq "MR3201A" ) {
	$imagename = "ath25/generic/lede-ath25-combined.squashfs.img";
} elsif ( $device eq "WNDR3800" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-wndr3800-squashfs-sysupgrade.bin";
} elsif ( $device eq "WZR600DHP" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-wzr-600dhp-squashfs-sysupgrade.bin";
} elsif ( $device eq "WDR3600" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-tl-wdr3600-v1-squashfs-sysupgrade.bin";
} elsif ( $device eq "WGT634U" ) {
	$imagename = "brcm47xx/legacy/lede-brcm47xx-legacy-standard-squashfs.trx";
} elsif ( $device eq "AIRROUTER" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-ubnt-airrouter-squashfs-sysupgrade.bin";
} elsif ( $device eq "RSTA" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-ubnt-rs-squashfs-sysupgrade.bin";
} elsif ( $device eq "ROCKET" ) {
	$imagename = "ar71xx/generic/lede-ar71xx-generic-ubnt-rocket-m-squashfs-sysupgrade.bin";
} elsif ( $device eq "MR24" ) {
	$imagename = "apm821xx/nand/lede-apm821xx-nand-mr24-squashfs-sysupgrade.tar";
}

system("mkdir -p output/usr/bin");
open( FIS, ">output/usr/bin/fetch_image.sh" );
print FIS <<EOF;
#!/bin/sh
cd /tmp
scp openwrt\@hawg:src/lede/bin/targets/$imagename /tmp/
EOF
system("chmod 755 output/usr/bin/fetch_image.sh");

open( WWW, "find splash -type f | grep -v .gitignore |" );

while (<WWW>) {
	chomp;
	my $src    = $_;
	my @path   = split( '/', $src );
	my $fname  = pop @path;
	shift(@path);
	my $outdir = join( '/', "output", "www", @path);
	my $dest   = join( '/', "output", "www", @path, $fname );

	# print "source = $src ; outdir = $outdir ; dest = $dest\n";

	my (
		$dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
		$size, $atime, $mtime, $ctime, $blksize, $blocks
	) = stat($src);

	unless ( -d $outdir ) { system("mkdir -p $outdir"); }

	print "sed -f foocab.sed < $src > $dest\n";

	system("sed -f foocab.sed < $src > $dest");

	chmod( $mode, $dest );
	chown( $uid, $gid, $dest );
}

system("pushd output/www ; ln -sf /tmp/users.html . ; popd");


sub getNodeInfoByNode {
	my $node     = shift;
	my $nodeinfo = {};
	my $url      = $APINODEBASE . $node;
	print $url, "\n" if $DEBUG;
	my $json = get($url);
	print Dumper($json) if $DEBUG;
	if ( defined($json) ) {
		$nodeinfo = decode_json($json);
		my $ret = $nodeinfo->{'data'};
		print Dumper($ret) if $DEBUG;
		return $ret;
	}
}

sub getNodeInfoByHost {
	my $host     = shift;
	my $nodeinfo = {};
	my $url      = $APIHOSTBASE . $host;
	print $url, "\n" if $DEBUG;
	my $json = get($url);
	print Dumper($json) if $DEBUG;
	if ( defined($json) ) {
		$nodeinfo = decode_json($json);
		my $ret = $nodeinfo->{'data'};
		print Dumper($ret) if $DEBUG;
		return $ret;
	}
}

my $imgname = "$node.png";
my $url = $IMGBASE . $imgname;
my $img = get($url);
if ( defined($img) ) {
	open( IMGOUT, "> output/www/images/$imgname")
		or die "couldn't write out downloaded image $imgname: " . $!;
	print IMGOUT $img;
	close IMGOUT;
} else {
	print "No node logo\n";
}	
