#!/usr/bin/env bash

/usr/local/bin/local-ifaces.sh;

for i in $(cat /srv/local/etc/.env/IFACE_LOCAL); do
  . /srv/local/etc/.env/${i}.iface;

  [[ -z $DEV || -z $NETVIA || -z $NETWORK || -z $NETMASK || -z $ADDR ]] && exit 1;

  cp /srv/local/etc/netplan-local.yaml /etc/netplan/99-local-${DEV}.yaml;

  sed -i "s|IFNAME|${DEV}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFROUTE|${NETVIA}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFNETWORK|${NETWORK}/${NETMASK}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFADDR|${ADDR}|g" /etc/netplan/99-local-${DEV}.yaml;

  unset DEV ADDR PREFIX NETMASK;
done

netplan generate;

for n in $(cat /srv/local/etc/.env/IFACE_LOCAL); do
  mkdir -pm0751 /etc/systemd/network/${n}.d;
  echo -e "[Network]\nKeepConfiguration=static\n" > /etc/systemd/network/${n}.d/override.conf;
  echo -e "# [Address]\n# AddPrefixRoute=false\n" >> /etc/systemd/network/${n}.d/override.conf;
  echo -e "# [Route]\n# GatewayOnlink=true\n" >> /etc/systemd/network/${n}.d/override.conf;
  chmod 0644 /etc/systemd/network/${n}.d/override.conf;
done

netplan apply;

exit 0;
