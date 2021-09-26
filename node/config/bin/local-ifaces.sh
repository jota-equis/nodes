#!/usr/bin/env bash

CONF=/srv/local/etc/.env

[[ -f ${CONF}/IFACE_LOCAL ]] && rm ${CONF}/IFACE_LOCAL;
[[ -f ${CONF}/LOCAL_CIDR ]] && LOCAL_CIDR=$(cat ${CONF}/LOCAL_CIDR);

for i in $(find /sys/class/net -type l -not -name eth0 -not -lname '*virtual*' -printf '%f ' | tr " " "\n" | sort ); do
  echo "${i}" >> ${CONF}/IFACE_LOCAL;
  echo "DEV=${i}" > ${CONF}/${i}.iface;

  ip -4 -f inet a show ${i} | awk '/inet/{ print $2 }' | awk -F "/" '{ print "DEVADDR="$1"\nDEVMASK="$2 }' >> ${CONF}/${i}.iface;
  ip -4 -f inet r | grep ${i} | grep via | awk '{ print $1"/"$3 }' | awk -F  "/" '{ print "NETWORK="$1"\nNETMASK="$2"\nNETGW="$3 }' >> ${CONF}/${i}.iface;

  [[ ! -z $LOCAL_CIDR ]] && echo "SUBNET=${LOCAL_CIDR}" >> ${CONF}/${i}.iface;
done

exit 0;
