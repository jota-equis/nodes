#!/usr/bin/env bash

CONF=/srv/local/etc/.env

[[ -f ${CONF}/IFACE_LOCAL ]] && rm ${CONF}/IFACE_LOCAL;

for i in $(find /sys/class/net -type l -not -name eth0 -not -lname '*virtual*' -printf '%f ' | tr " " "\n" | sort ); do
  echo "${i}" >> ${CONF}/IFACE_LOCAL;
  echo "DEV=${i}" > ${CONF}/${i}.iface;
  ip -4 -f inet a show ${i} | awk '/inet/{ print "ADDR="$2 }' >> ${CONF}/${i}.iface;
done

exit 0;
