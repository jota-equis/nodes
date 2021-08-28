#!/usr/bin/env bash

for i in $(cat /srv/local/etc/.env/IFACE_LOCAL); do
  . /srv/local/etc/.env/${i}.iface;

  cp /srv/local/etc/netplan-local.yaml /etc/netplan/99-local-${DEV}.yaml;
  
  PREFIX=$(echo $ADDR |  awk -F  "." '{ print $1"."$2".0." }');

  sed -i "s|ens00:|${DEV}:|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|192.168.0.|${PREFIX}|g" /etc/netplan/99-local-${DEV}.yaml;
  sed -i "s|addresses:.*|addresses: [${ADDR}]|g" /etc/netplan/99-local-${DEV}.yaml;

  unset DEV ADDR PREFIX;
done

netplan generate;

for n in $(cat /srv/local/etc/.env/IFACE_LOCAL); do
  mkdir -pm0751 /etc/systemd/network/${n}.d;
  echo -e "[Network]\nKeepConfiguration=static\n" > /etc/systemd/network/${n}.d/override.conf;
  echo -e "# [Address]\n# AddPrefixRoute=false\n" >> /etc/systemd/network/${n}.d/override.conf;
  echo -e "# [Route]\n# GatewayOnlink=true\n" >> /etc/systemd/network/${n}.d/override.conf;
  chmod 0644 /etc/systemd/network/${n}.d/override.conf;
done

exit 0;
