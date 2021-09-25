#!/usr/bin/env bash

CONF=/srv/local/etc/.env

[[ -f ${CONF}/IFACE_LOCAL ]] && rm ${CONF}/IFACE_LOCAL;
[[ -f ${CONF}/LOCAL_CIDR ]] && LOCAL_CIDR=$(cat ${CONF}/LOCAL_CIDR);

for i in $(find /sys/class/net -type l -not -name eth0 -not -lname '*virtual*' -printf '%f ' | tr " " "\n" | sort ); do
  echo "${i}" >> ${CONF}/IFACE_LOCAL;
  echo "DEV=${i}" > ${CONF}/${i}.iface;
  ip -4 -f inet a show ${i} | awk '/inet/{ print "ADDR="$2 }' >> ${CONF}/${i}.iface;

  if [[ ! -z $LOCAL_CIDR ]]; then
    echo $LOCAL_CIDR | awk -F  "/" '{ print "NETWORK="$1"\nNETMASK="$2 }' >> ${CONF}/${i}.iface;
  else
    ip -4 -f inet r | grep ${i} | grep link | awk '{ print "NETWORK="$1 }' >> ${CONF}/${i}.iface;
    ip -4 -f inet r | grep ${i} | grep via | awk '{ print $1 }' | awk -F  "/" '{ print "NETMASK="$2 }' >> ${CONF}/${i}.iface;
  fi
done

exit 0;
