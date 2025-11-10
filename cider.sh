#!/bin/bash
#####################################
VERSION="0.1"
NAME="Cider"
AUTHOR="RadicalEd"
DESCRIPTION="check if IP addresses are within CIDR addresses"
LICENSE=""
PROGRAM=$0
BANNERCOLOR="cyan"
HIGHLIGHT="red"
#####################################
# Printing Functions

c () { # Set/Clear Colors
	case "${1}" in
		(black)	  tput setaf 0;;
		(red)		tput setaf 1;;
		(green)	  tput setaf 2;;
		(yellow)	 tput setaf 3;;
		(blue)	   tput setaf 4;;
		(magenta)	tput setaf 5;;
		(cyan)	   tput setaf 6;;
		(white)	  tput setaf 7;;
		(bg_black)   tput setab 0;;
		(bg_red)	 tput setab 1;;
		(bg_green)   tput setab 2;;
		(bg_yellow)  tput setab 3;;
		(bg_blue)	tput setab 4;;
		(bg_magenta) tput setab 5;;
		(bg_cyan)	tput setab 6;;
		(bg_white)   tput setab 7;;
		(n)		  tput sgr0;;
		(none)	   tput sgr0;;
		(clear)	  tput sgr0;;
	esac
}

banner () {
cat << 'EOF' >&2
    ______    __     ________    _______   _______   
   /" _  "\  |" \   |"      "\  /"     "| /"      \  
  (: ( \___) ||  |  (.  ___  :)(: ______)|:        | 
   \/ \      |:  |  |: \   ) || \/    |  |_____/   ) 
   //  \ _   |.  |  (| (___\ || // ___)_  //      /  
  (:   _) \  /\  |\ |:       :)(:      "||:  __   \  
   \_______)(__\_|_)(________/  \_______)|__|  \___) 
EOF
}


usage () {
c "$BANNERCOLOR"
banner
c n

cat << EOF >&2

$(c $HIGHLIGHT)$NAME$(c n) v$VERSION - Written By $(c $HIGHLIGHT)$AUTHOR$(c n)

$(echo -n "	$DESCRIPTION" | fmt -w $(tput cols))

$(c $HIGHLIGHT)USAGE$(c n): $PROGRAM [-h] <url/ip/list> <CIDR...>

	-h : show usage

	<url/ip/list> : IP, Url, Domain, or a file that lists these
	<CIDR...>	  : CIDR addresses, can also be list files

	This tool is useful to check if hosts are within scope.
EOF
}

error () {
	code="$1";shift
	case "$code" in
		(1) usage;;
	esac
	echo "Error $code: $*" >&2
	exit "$code"
}

warn () {
	echo "$(c yellow)[Warning]$(c n) $*" >&2
}

hr () { # Horizontal Rule
	character="${1:--}"
	printf -v _hr "%*s" $(tput cols) && echo "${_hr// /$character}";
}


# End of Printing Functions
#####################################
# Arguments

while getopts "h" o;do
	case "${o}" in
		(h) usage && exit;;
		(*) echo "Try Using $PROGRAM -h for Help And Information" >&2 && exit 1;;
	esac
done

shift $((OPTIND-1))

ip_source="${1}"
shift

range_sources="$*"

[ ! "$ip_source" ] && error 1 "Need to Specify an ip, url, or a file that lists ips/urls"
[ ! "$range_sources" ] && error 1 "Need to Specify atleast one CIDR address, or a file listing CIDR addresses."

# End of Arguments
#####################################
# Functions

resolve_host() {
	local address="$1"
	# resolve address to an ip address if necessary
	if [[ "$address" =~ [a-zA-Z] ]];then
		if [[ "$address" =~ ^http ]];then
			address="$(cut -d '/' -f 3 <<< "$address")"
		fi
		address="$(host "$address" | grep "has address" | head -n1 | awk '{ print $4 }')"
	fi
	echo "$address"
}

valid_ipv4() {
	local ip="${1}"
	[[ "${ip}" =~ ^(([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))\.){3}([1-9]?[0-9]|1[0-9][0-9]|2([0-4][0-9]|5[0-5]))$ ]]
	return "$?"
}

valid_cidr() {
	local ip_cidr="${1}"
	local status=1
	if [[ "${ip_cidr}" =~ ^[^/]*/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
		local ip=$(echo "${ip_cidr}" | cut -d '/' -f 1)
		valid_ipv4 "${ip}" && status=0
	fi
	return "${status}"
}

is_address_in_range () {

	# validation
	local range="$2"
	valid_cidr "$range" || return 3

	local address="$1"
	valid_ipv4 "$address" || return 4


	# check if address is in range (had to google this)
	IFS=/ read -r sub mask <<< "$range"
	ip_a=(${address//./ })
	sub_ip=(${sub//./ })
	netmask=$((0xFFFFFFFF << (32 - mask) & 0xFFFFFFFF))

	start=0
	for octet in "${sub_ip[@]}"; do
		start=$((start << 8 | octet))
	done

	start=$((start & netmask))
	end=$((start | ~netmask & 0xFFFFFFFF))

	ip_num=0
	for octet in "${ip_a[@]}"; do
		ip_num=$((ip_num << 8 | octet))
	done

	((ip_num >= start && ip_num <= end))
}

# End of Functions
#####################################
# Execution

	# Build List of Ranges
ranges=()
for range in $range_sources;do
	if [ -f "$range" ];then
		while read rng;do
			if valid_cidr "$rng";then
				ranges+=("$rng")
			else
				warn "Bad CIDR $rng"
			fi
		done < "$range"
	else
		if valid_cidr "$range";then
			ranges+=("$range")
		else
			warn "Bad CIDR $range"
		fi
	fi
done

	# Build List of Addresses
addresses=()
if [ -f "$ip_source" ];then
	while read addr;do
		ipv4="$(resolve_host "$addr")"
		if valid_ipv4 "$ipv4";then
			addresses+=("$addr|$ipv4")
		else
			warn "Bad IPV4 for $addr"
		fi
	done < "$ip_source"
else
	ipv4="$(resolve_host "$ip_source")"
	if valid_ipv4 "$ipv4";then
		addresses+=("$ip_source|$ipv4")
	else
		warn "Bad IPV4 for $ip_source"
	fi
fi

	# Check Each Address With Each Range
for address_line in ${addresses[*]};do
	address="${address_line/|*/}"
	ipv4="${address_line/*|/}"
	for range in ${ranges[*]};do
		is_address_in_range "$ipv4" "$range"
		case "$?" in
			(0) echo "$address	$ipv4	$range";;
		esac
	done
done

# End of Execution
#####################################
