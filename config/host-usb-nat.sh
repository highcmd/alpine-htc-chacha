#!/bin/sh
# Host side: give the ChaCha (172.16.42.1 over USB RNDIS) internet via NAT.
# Usage: sudo ./host-usb-nat.sh [up|down]   (not persistent across host reboot)
set -e
WAN=$(ip route show default | awk '{print $5; exit}')
IF=$(ip -br link | awk '/^enx02c4a0000001/{print $1; exit}')
[ -n "$IF" ] || IF=$(ip -br link | awk '/^enx/{print $1; exit}')
[ -n "$IF" ] || { echo "no RNDIS interface (enx*)"; exit 1; }
if [ "${1:-up}" = down ]; then
	iptables -t nat -D POSTROUTING -s 172.16.42.0/24 -o "$WAN" -j MASQUERADE || true
	iptables -D DOCKER-USER -s 172.16.42.0/24 -j ACCEPT || true
	iptables -D DOCKER-USER -d 172.16.42.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT || true
	exit 0
fi
# NM profile "chacha-usb" (MAC 02:c4:a0:00:00:01) normally assigns the address;
# fall back to manual setup for a random-MAC interface.
if ! ip -4 addr show "$IF" | grep -q 172.16.42.2; then
	nmcli dev set "$IF" managed no 2>/dev/null || true
	ip addr replace 172.16.42.2/24 dev "$IF"
	ip link set "$IF" up
fi
sysctl -q -w net.ipv4.ip_forward=1
iptables -t nat -C POSTROUTING -s 172.16.42.0/24 -o "$WAN" -j MASQUERADE 2>/dev/null ||
	iptables -t nat -A POSTROUTING -s 172.16.42.0/24 -o "$WAN" -j MASQUERADE
iptables -C DOCKER-USER -s 172.16.42.0/24 -j ACCEPT 2>/dev/null ||
	iptables -I DOCKER-USER -s 172.16.42.0/24 -j ACCEPT
iptables -C DOCKER-USER -d 172.16.42.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
	iptables -I DOCKER-USER -d 172.16.42.0/24 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
echo "NAT up: $IF -> $WAN"
