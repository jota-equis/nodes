#!/usr/bin/env bash

/usr/local/bin/local-ifaces.sh;

for i in $(cat /srv/local/etc/.env/IFACE_LOCAL); do
  . /srv/local/etc/.env/${i}.iface;

  [[ -z $DEV || -z $DEVADDR || -z $DEVMASK || -z $NETWORK || -z $NETMASK || -z $NETGW ]] && exit 1;

  cp /srv/local/etc/netplan-local.yaml /etc/netplan/99-local-${DEV}.yaml;

  sed -i "s|DEVNAME|${DEV}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFROUTE|${NETGW}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFNETWORK|${NETWORK}/${NETMASK}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|IFADDR|${DEVADDR}|g" /etc/netplan/99-local-${DEV}.yaml;

  NEWDEV=$(awk '/set-name/{ print $2 }' /etc/netplan/99-local-${DEV}.yaml);
  
  if [[ ! -z $NEWDEV && ! $NEWDEV = $DEV ]]; then
    echo "${NEWDEV}" >> /srv/local/etc/.env/IFACE_LOCAL_NEW;
    mv /etc/netplan/99-local-${DEV}.yaml /etc/netplan/99-local-${NEWDEV}.yaml;
  fi

  unset DEV DEVADDR DEVMASK NETWORK NETMASK NETGW;
done

[[ -f /srv/local/etc/.env/IFACE_LOCAL_NEW ]] && mv /srv/local/etc/.env/IFACE_LOCAL_NEW /srv/local/etc/.env/IFACE_LOCAL;

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
