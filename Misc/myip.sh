#!/bin/bash
#
# K4S1
#

#debug=1

#** Collect IPv4 on interfaces  **#
declare -A MyActiveDevices
while read a; do
  [ $debug ] && echo $a
  dev=$(echo $a | cut -f1 -d-)
  ip=$(echo $a | cut -f2 -d-)
  MyActiveDevices+=([$dev]=$ip)
done <<<$(ip a | grep 'state UP' -A2 | grep 'inet' | awk '{print $NF"-"$2}')

#** Collect IP route **#
declare -a MyDefaultGW
declare -a MyStaticRoute
while read a; do
  [ $debug ] && echo "IP route line: "$a
  case "$a" in 
  default*)
    a2=$(echo $a | awk '{print $3"-"$NF"-"$5}')
    ip=$(echo $a2 | cut -f1 -d-)
    metric=$(echo $a2 | cut -f2 -d-)
    dev=$(echo $a2 | cut -f3 -d-)
    [ $debug ] && echo "IP route line: "$ip" - "$metric" - "$dev
    MyDefaultGW+=("$metric-$ip-$dev")
    ;;
  *proto?static*)
    ip=$(echo $a | sed 's/ dev.*$//')
    dev=$(echo $a | sed 's/^.* dev //' | sed 's/ proto.*$//')
    metric=$(echo $a | awk '{print $NF}')
    [ $debug ] && echo "Static Route: "$ip" - "$dev" - "$metric
    MyStaticRoute+=("$ip-$dev-$metric")
    ;;
  esac 
done <<<$(ip route)

#** Collect IPv4 default DNS Servers **#
declare -a MyNameSrv
while read a; do
  [ $debug ] && echo $a
  MyNameSrv+=($a)
done <<<$(grep 'nameserver' /etc/resolv.conf | awk '{print $2}')

#** Collect Public IP **#
PubIP=$(dig +short myip.opendns.com @resolver1.opendns.com)

#** Write to screen **

for key in "${!MyActiveDevices[@]}"
do
  echo "$key : "${MyActiveDevices[$key]}
  for key2 in "${!MyStaticRoute[@]}"
  do
    tmp=$(echo ${MyStaticRoute[$key2]} | awk -F- '{print $2}')
    if [ "$tmp" == "$key" ]
    then
      echo "  Static: "$(echo ${MyStaticRoute[$key2]} | cut -f1 -d-)" Metric: "$(echo ${MyStaticRoute[$key2]} | cut -f3 -d-)
    fi
  done
  for key3 in "${!MyDefaultGW[@]}"
  do
    if [ "$(echo ${MyDefaultGW[$key3]} | cut -f3 -d-)" == "$key"  ]
    then
      echo "  DefaGW: "$(echo ${MyDefaultGW[$key3]} | cut -f2 -d-)" Metric: "$(echo ${MyDefaultGW[$key3]} | cut -f1 -d-)
    fi
  done
  echo " "
done
for key in "${!MyNameSrv[@]}"
do
  echo "NameSrv"$(echo $(expr $key + 1))": "${MyNameSrv[$key]}
done | sort
echo "Public  : "$PubIP
