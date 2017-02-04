#
# https://agentoss.wordpress.com/2011/10/31/creating-a-wireless-access-point-with-debian-linux/
# http://www.christianix.de/linux-tutor/hostapd.html
# https://wireless.wiki.kernel.org/welcome

#
touch /etc/rc.local
chmod +x /etc/rc.local
#
sed -i -e '/exit 0/d' /etc/rc.local
sed -i -e 's/sh -e/sh/' /etc/rc.local
#

apt install -y conntrack

cat <<'EOF' > /usr/sbin/ipmgr.sh
#!/bin/bash
#
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
#

LOCALNETS='10.0.0.0/8 172.16.0.0/12 192.168.0.0/24'
# ADDLIST="10.236.13.1/24 198.20.13.1/24 198.19.8.1/24"
ADDLIST=""
DEV=""

dlog(){
    logger --stderr -p user.notice -t "$0[monitor:$$]" -- "$@"
}

plog(){
    local line=''
    while read line
    do
        dlog "$line"
    done
}

getgwaddr(){
  local routedev="$1"
  test -z "$routedev" && routedev='.'
  route -n | grep $routedev | grep '^0.0.0.0' | while read aaa
  do
    gwaddr="$(echo $aaa | awk '{print $2}')";
    test "$gwaddr" == "0.0.0.0" && continue;
    test -z "$gwaddr" && continue;
    echo $gwaddr;
    break;
  done
}

getgwdev(){
  local routedev="$1"
  test -z "$routedev" && routedev='.'
  route -n | grep $routedev | grep '^0.0.0.0' | while read aaa
  do
    gwdev="$(echo $aaa | awk '{print $8}')";
    test "$gwdev" == "lo" && continue;
    test -z "$gwdev" && continue;
    echo $gwdev;
    break;
  done
}

showstat(){
    local arg="$1"
    test -z "$IPMGRQUIET" -o -n "$arg" && test -n "$DEV" && ip addr list dev $DEV
    test -z "$IPMGRQUIET" -o -n "$arg" && route -n
    test -z "$IPMGRQUIET" -o -n "$arg" && echo " --- "
    test -z "$IPMGRQUIET" -o -n "$arg" && iptables -L POSTROUTING -nv -t nat && iptables -L FORWARD -n -v
}

gwmonitor(){
    if [ -z "$DEV" ]
    then
        echo "ERROR: DEV not defined."
        exit 1
    fi
    if [ -z "$GWIP" ]
    then
        echo "ERROR: GWIP not defined."
        exit 1
    fi
    local delay=5
    local loss=0
    local monpid=$$
    local oldpids=`ps axuww|grep "/usr/sbin/ipmgr.sh monitor" | grep -v grep | awk '{print $2}'`
    ps axuww|grep "/usr/sbin/ipmgr.sh monitor" | grep -v grep
    echo "monpid: $monpid"
    echo "oldpids: $oldpids"
    for onepid in $oldpids
    do
        test $onepid -ge $monpid && echo "skipped: $onepid" && continue
        kill $onepid 2>/dev/null
        if [ $? -eq 0 ]
        then
            echo "WARNING: old monitor $onepid killed"
        fi
        kill -9 $onepid 2>/dev/null
    done
    echo "monitor $monpid for $GWIP running ..."
    while [ : ]
    do
        loss=`ping -c 3 -w 3 $GWIP 2>&1 | grep 'packet loss' | tr ',%' ' '|awk '{print $6}'`
        if [ $loss -ge 10 ]
        then
            echo "ERROR: ${loss}% packet loss(> 10%), try to restart NIC $DEV ..."
            ifdown $DEV;ifdown $DEV;ifdown $DEV;
            ifup $DEV
            sleep $delay
            let delay=$delay+5
        else
            test $delay -gt 5 && echo "restart NIC $DEV OK"
            delay=5
        fi
    done
}

if [ `id -u` -ne 0 ]
then
    sudo $0 $@
    exit $?
fi

if [ -z "$PLOGGING" ]
then
    export PLOGGING='yes'
    $0 $@ 2>&1 | plog
    exit $?
fi

debug=0
if [ "$1" = "-D" ]
then
    shift
    set -x
fi

STOPFW=0
test "$1" = 'stop' && STOPFW=1 && shift

MSSVAL=65535
if [ "$1" = "-m" ]
then
    expr 1 + $2 >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
        MSSVAL="$2"
        shift
        shift
    else
        shift
        echo "Invalid TCPMSS $2, ignored"
    fi
fi

test "$1" = 'show' && SHOW="on" && shift

echo "- TCPMSS $MSSVAL"

test -n "$1" -a "$1" != 'monitor' && DEV="$1"
test -z "$DEV" && DEV="$(getgwdev)"
GWTIME=''
if [ -n "$IPMGRWAITGW" -a -z "$DEV" -a $STOPFW -eq 0 -a -z "$SHOW" ]
then
    echo "waiting for gateway(30 seconds) ..."
    for aaa in `seq 1 30`
    do
        DEV="$(getgwdev)"
        if [ -n "$DEV" ]
            then
            GWTIME="$aaa"
            break
        fi
        sleep 1
    done
fi

if [ -z "$DEV" -a -n "$SHOW" ]
  then
  DEV='lo'
fi

if [ -z "$DEV" ]
  then
  test -z "$IPMGRQUIET" && route -n
  echo "ERROR: probe default gateway device failed."
  exit 1
fi

GWIP="$(getgwaddr $DEV)"

if [ -z "$GWIP" -a -n "$SHOW" ]
  then
  gw='127.0.0.1'
fi

if [ -z "$GWIP" ]
  then
  test -z "$IPMGRQUIET" && route -n 
  echo "ERROR: probe default gateway from $DEV failed."
  exit 1
fi

test -n "$GWTIME" && echo "Probe got gateway device $GWIP // $DEV after $GWTIME sceonds."

test -n "$SHOW" && showstat on && exit 0

#
if [ "$1" = 'monitor' ]
then
    if [ -z "$RUNMON" ]
    then
        export RUNMON='yes'
        nohup $0 monitor </dev/zero >> /var/log/ipmgr.log 2>&1 &
        exit $?
    fi
    gwmonitor 2>&1 | plog
    exit $?
fi

/usr/sbin/conntrack -F >/dev/null

for aaa in $ADDLIST
do
  if [ $STOPFW -ne 0 ]
  then
      ip addr del $aaa dev $DEV 2>/dev/null
  else
      # add no existed ip
      ip route list | grep -q "inet ${aaa} " || ip addr add $aaa dev $DEV
  fi
done

for aaa in $LOCALNETS
do 
  if [ $STOPFW -ne 0 ]
  then
      route delete -net $aaa gw $GWIP 2>/dev/null
  else
      # add no existed net
      ip route list | grep -q "^$aaa " || route add -net $aaa gw $GWIP
  fi
done
gwdev="$(getgwdev)"
if [ -n "$GWIP" ]
  then
    for aaa in 1 2 3 4 5 6 7 8
    do
       mssline=`iptables-save | grep 'TCPMSS' | sed -e 's#^-A #-D #g'`
       test -n "$mssline" && /sbin/iptables $mssline
       masqline=`iptables-save | grep 'MASQUERADE' | sed -e 's#^-A #-D #g'`
       test -n "$masqline" && /sbin/iptables -t nat $masqline
    done
    if [ $STOPFW -eq 0 ]
    then
        if [ $MSSVAL -ne 0 ]
        then
            test $MSSVAL -ne 65535 && /sbin/iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSSVAL
        else
            /sbin/iptables -I FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        fi
        /sbin/iptables -I POSTROUTING -t nat -o $gwdev -j MASQUERADE
        sysctl -q -w net.ipv4.ip_forward=1
        modprobe nf_nat_pptp
        modprobe nf_conntrack_pptp
        modprobe nf_nat_proto_gre
        modprobe nf_conntrack_proto_gre
        modprobe nf_conntrack_ftp
        #
        echo '7875' > /proc/sys/net/netfilter/nf_conntrack_generic_timeout
        #
        echo '7200' > /proc/sys/net/netfilter/nf_conntrack_udp_timeout
        #
        # https://dev.openwrt.org/ticket/12976
        echo '14400' > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
    fi
else
  test -z "$IPMGRQUIET" && route -n
  echo "ERROR: probe default gateway from ANY failed."
  exit 1
fi
showstat
if [ $STOPFW -ne 0 ]
then
    echo "NETFILTER MASQUERADE deactivated on $gwdev"
else
    echo "NETFILTER MASQUERADE activated on $gwdev"
fi
#
EOF

chmod +x /usr/sbin/ipmgr.sh

/usr/sbin/ipmgr.sh

echo 'IPMGRWAITGW=yes IPMGRQUIET=yes /usr/sbin/ipmgr.sh' >> /etc/rc.local

#

# https://w1.fi/hostapd/

#
lspci

# 04:00.0 Network controller: Qualcomm Atheros AR5418 Wireless Network Adapter [AR5008E 802.11(a)bgn] (PCI-Express) (rev 01)

#
# Atheros AR5418 MAC/BB Rev:2 AR5133 RF Rev:81 mem=0xffffc90004f20000, irq=16

lsusb
# Bus 002 Device 009: ID 0bda:8178 Realtek Semiconductor Corp. RTL8192CU 802.11n WLAN Adapter

dmesg | grep -C 5 wlan

modprobe -r ath9k

modprobe -vv ath9k

modprobe -r rtl8192cu
modprobe -vv rtl8192cu

dmesg | grep -C 3 wlan
#

# [ 3389.977425] rtl8192cu: Board Type 0
# [ 3389.977669] rtl_usb: rx_max_size 15360, rx_urb_num 8, in_ep 1
# [ 3389.977712] rtl8192cu: Loading firmware rtlwifi/rtl8192cufw_TMSC.bin
# [ 3389.977869] ieee80211 phy2: Selected rate control algorithm 'rtl_rc'
# [ 3389.978190] usbcore: registered new interface driver rtl8192cu
# [ 3389.979852] rtl8192cu 2-1.1:1.0 wlp3s0: renamed from wlp3s0
# [ 3390.021933] IPv6: ADDRCONF(NETDEV_UP): wlp3s0: link is not ready


iwconfig

# br0       no wireless extensions.
# 
# vboxnet0  no wireless extensions.
# 
# wlp3s0  IEEE 802.11  ESSID:off/any  
#           Mode:Managed  Access Point: Not-Associated   Tx-Power=0 dBm   
#           Retry short limit:7   RTS thr=2347 B   Fragment thr:off
#           Encryption key:off
#           Power Management:on
#           
# enp2s0    no wireless extensions.
# 
# wlp3s0    IEEE 802.11  ESSID:off/any  
#           Mode:Managed  Access Point: Not-Associated   Tx-Power=0 dBm   
#           Retry short limit:7   RTS thr:off   Fragment thr:off
#           Encryption key:off
#           Power Management:off
#           
# enx00e04c046129  no wireless extensions.
# 
# lo        no wireless extensions.
# 

ifconfig wlp3s0 up

#

iw wlp3s0 scan

# BSS 8c:be:be:27:08:01(on wlp3s0)
# 	TSF: 21815073217 usec (0d, 06:03:35)
# 	freq: 2422
# 	beacon interval: 100 TUs
# 	capability: ESS Privacy ShortSlotTime RadioMeasure (0x1411)
# 	signal: -48.00 dBm
# 	last seen: 592 ms ago
# 	Information elements from Probe Response frame:
# 	SSID: Xiaomi_0800
# 	Supported rates: 1.0* 2.0* 5.5* 11.0* 18.0 24.0 36.0 54.0 
# 	DS Parameter set: channel 3
# 	ERP: <no flags>
# 	ERP D4.0: <no flags>
# 	RSN:	 * Version: 1
# 		 * Group cipher: TKIP
# 		 * Pairwise ciphers: CCMP TKIP
# 		 * Authentication suites: PSK
# 		 * Capabilities: 16-PTKSA-RC 1-GTKSA-RC (0x000c)

#
# networking setup, check main install doc for dnsmasq(dns server/dhcp server), netfilter snat
#

# wifi client:
# https://linuxconfig.org/etcnetworkinterfacesto-connect-ubuntu-to-a-wireless-network
# http://askubuntu.com/questions/168687/wireless-configuration-using-etc-network-interfaces-documentation

apt-get install -y bridge-utils ebtables hostapd

# http://www.techrepublic.com/article/pro-tip-take-back-control-of-resolv-conf/
sed -i -e 's/^dns=dnsmasq/#dns=dnsmasq/g' /etc/NetworkManager/NetworkManager.conf

rm -f /etc/resolv.conf

cat <<'EOF'> /etc/resolv.conf
search localdomain
nameserver 8.8.8.8
EOF

# wifi relay only

#
# networking with hostapd softap
#
# interfaces(5) file used by ifup(8) and ifdown(8)
auto lo
iface lo inet loopback

# pci wifi link ath9, for hostapd
auto wlp3s0
iface wlp3s0 inet manual 

# wired link
auto enp2s0
iface enp2s0 inet manual 

# hostapd bridge
auto br0
iface br0 inet static
  address 172.16.0.1
  netmask 255.255.255.0
  bridge_ports enp2s0

# usb wifi link, can not add wifi client to bridge
auto wlx14cf92141210
iface wlx14cf92141210 inet dhcp
	post-up /usr/sbin/ipmgr.sh
    wpa-ssid Xiaomi_0800
    wpa-psk yourpassword
    #wpa-ssid tutux-136-mini
    #wpa-psk yourpassword
#


service network-manager restart

# need stop first
service networking stop

service networking start

# NOTE: 5G AP is no support by AR9280

dmesg |grep -C 5 phy

dmesg |grep -C 5 wlan

# NOTE: phy0 may not == wlp3s0, check dmesg

dmesg | grep -C 5 phy0
# [   15.996259] Bluetooth: HCI device and connection manager initialized
# [   15.996262] Bluetooth: HCI socket layer initialized
# [   15.996264] Bluetooth: L2CAP socket layer initialized
# [   15.996269] Bluetooth: SCO socket layer initialized
# [   15.998228] Linux video capture interface: v2.00
# [   15.999673] ieee80211 phy0: Selected rate control algorithm 'minstrel_ht'
# [   16.000019] ieee80211 phy0: Atheros AR9485 Rev:1 mem=0xffffba71cfe80000, irq=18
# [   16.001649] snd_hda_codec_realtek hdaudioC1D0: autoconfig for ALC668: line_outs=2 (0x14/0x1a/0x0/0x0/0x0) type:speaker
# [   16.001650] snd_hda_codec_realtek hdaudioC1D0:    speaker_outs=0 (0x0/0x0/0x0/0x0/0x0)
# [   16.001651] snd_hda_codec_realtek hdaudioC1D0:    hp_outs=1 (0x15/0x0/0x0/0x0/0x0)
# [   16.001651] snd_hda_codec_realtek hdaudioC1D0:    mono: mono_out=0x0
# [   16.001652] snd_hda_codec_realtek hdaudioC1D0:    inputs:
# 

# for card info
iw phy phy0 info

iw phy phy0 info | grep -A 20 'Supported interface modes'

# need AP for hostapd

# 	Supported interface modes:
# 		 * IBSS
# 		 * managed
# 		 * AP
# 		 * AP/VLAN
# 		 * WDS
# 		 * monitor
# 		 * mesh point
# 		 * P2P-client
# 		 * P2P-GO
# 		 * Unknown mode (11)
# 	Band 1:
# 		Capabilities: 0x116e
# 			HT20/HT40
# 			SM Power Save disabled
# 			RX HT20 SGI
# 			RX HT40 SGI
# 			RX STBC 1-stream
# 			Max AMSDU length: 3839 bytes
# 			DSSS/CCK HT40
# 		Maximum RX AMPDU length 65535 bytes (exponent: 0x003)

iwlist wlp3s0 freq

iw list

cat <<'EOF' >/etc/hostapd/hostapd.conf
#
# https://w1.fi/cgit/hostap/plain/hostapd/hostapd.conf
#
interface=wlp3s0
driver=nl80211

# Operation mode (a = IEEE 802.11a, b = IEEE 802.11b, g = IEEE 802.11g)
hw_mode=g
channel=6
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_passphrase=yourpassword
wpa_pairwise=CCMP

# SSID to be used in IEEE 802.11 management frames
# md5sum h8 from 136
ssid=aluminium-136

# Country code (ISO/IEC 3166-1).
country_code=US
#country_code=CN

#
# YOUR BRIDGE NAME
bridge=br0

# Module bitfield: -1 = all
logger_syslog=-1
# Levels: 0 (verbose debug), 1 (debug), 2 (info), 3 (notify), 4 (warning)
logger_syslog_level=2
# Module bitfield: -1 = all
logger_stdout=-1
# Levels: 0 (verbose debug), 1 (debug), 2 (info), 3 (notify), 4 (warning)
logger_stdout_level=4
#
EOF

# hide password
chmod 600 /etc/hostapd/hostapd.conf
# debug: Launch hostapd in non-daemon mode, and go try to associate to your newly created AP with another computer

hostapd /etc/hostapd/hostapd.conf -d

hostapd /etc/hostapd/hostapd.conf -dd

hostapd /etc/hostapd/hostapd.conf

#

cat <<'EOF' > /etc/default/hostapd
# Defaults for hostapd initscript
#
# See /usr/share/doc/hostapd/README.Debian for information about alternative
# methods of managing hostapd.
#
# Uncomment and set DAEMON_CONF to the absolute path of a hostapd configuration
# file and hostapd will be started during system boot. An example configuration
# file can be found at /usr/share/doc/hostapd/examples/hostapd.conf.gz
#
#DAEMON_CONF=""

# Additional daemon options to be appended to hostapd command:-
#   -d   show more debug messages (-dd for even more)
#   -K   include key data in debug messages
#   -t   include timestamps in some debug messages
#
# Note that -B (daemon mode) and -P (pidfile) options are automatically
# configured by the init.d script and must not be added to DAEMON_OPTS.
#
#DAEMON_OPTS=""
DAEMON_CONF="/etc/hostapd/hostapd.conf"
DAEMON_OPTS="-t"
#
EOF

#

#
# on boot
#

service hostapd start

# set wifi txpower
# 3-16db
echo '/sbin/iwconfig wlp3s0 txpower 10' >> /etc/rc.local

#
# TODO: hotspot + anti-gfw
# # http://people.apache.org/~amc/tiphares/bridge.html

apt-get install -y dnsmasq

cat <<'EOF'> /etc/dnsmasq.conf
#
# port=0 to disable dns server part
#
port=53
#
no-resolv

server=8.8.8.8
server=192.168.31.1

# server=114.114.114.114
# server=8.8.8.8
# server=/google.com/8.8.8.8

all-servers

#
log-queries
#
# enable dhcp server
#
dhcp-range=172.16.0.51,172.16.0.90,2400h
#
#
log-dhcp
#
#
no-dhcp-interface=em0
#
#dhcp-range=vmbr0,10.236.12.21,10.236.12.30,3h
# option 6, dns server
#dhcp-option=vmbr0,6,10.236.8.8
# option 3, default gateway
#dhcp-option=vmbr0,3,10.236.12.1
# option 15, domain-name
#dhcp-option=vmbr0,15,localdomain
# option 119, domain-search
#dhcp-option=vmbr0,119,localdomain
#
#dhcp-range=vmbr9,198.119.0.21,198.119.0.199,3h
# option 6, dns server
#dhcp-option=vmbr9,6,198.119.0.11
# option 3, default gateway
#dhcp-option=vmbr9,3,198.119.0.11
# option 15, domain-name
#dhcp-option=vmbr9,15,localdomain
# option 119, domain-search
#dhcp-option=vmbr9,119,localdomain
#
# dhcp options
#
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 DHCPOFFER(vmbr0) 10.236.12.180 36:b8:a4:ad:46:05 
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 requested options: 1:netmask, 28:broadcast, 2:time-offset, 3:router, 
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 requested options: 15:domain-name, 6:dns-server, 119:domain-search, 
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 requested options: 12:hostname, 44:netbios-ns, 47:netbios-scope, 
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 requested options: 26:mtu, 121:classless-static-route, 42:ntp-server
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 next server: 10.236.12.11
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  1 option: 53 message-type  2
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option: 54 server-identifier  10.236.12.11
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option: 51 lease-time  10800
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option: 58 T1  5400
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option: 59 T2  9450
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option:  1 netmask  255.255.255.0
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option: 28 broadcast  10.236.12.255
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option:  3 router  10.236.12.11
#Nov  7 21:40:18 b2c-dc-pve1 dnsmasq-dhcp[8620]: 3744951815 sent size:  4 option:  6 dns-server  10.236.12.11
#
EOF

#

service dnsmasq restart

cat <<'EOF'>/etc/resolv.conf
#
search localdomain
nameserver 127.0.0.1
#
EOF

# SNAT for hostapd


#
# iptables/netfilter max connection track
# change 16384 => 60240, max connections from 65535 => 481920

#[   43.629675] ip_tables: (C) 2000-2006 Netfilter Core Team
#[   43.633534] nf_conntrack version 0.5.0 (16384 buckets, 65536 max)

#[   43.661511] ip_tables: (C) 2000-2006 Netfilter Core Team
#[   43.672617] nf_conntrack version 0.5.0 (60240 buckets, 481920 max)

#make sure no dup item
for onefile in `ls -A  /etc/modprobe.d/* | grep -v blacklist`
do
cat $onefile | grep -v 'ip_conntrack' | grep -v 'nf_conntrack'> /tmp/mod.tmp 
cat /tmp/mod.tmp > $onefile
rm -f /tmp/mod.tmp
done

touch /etc/modprobe.d/nf_conntrack.conf
echo 'options nf_conntrack hashsize=60240' >> /etc/modprobe.d/nf_conntrack.conf
cat /etc/modprobe.d/nf_conntrack.conf
