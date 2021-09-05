#!/usr/bin/env bash
exec 1> >(logger -s -t $(basename $0)) 2>&1
# · ---
export DEBIAN_FRONTEND=noninteractive
# · ---
SYS_LANG="${1:-es_ES}"
SSH_PORT=22
MASTER=
DOMAIN=
ROLE=
TOKEN=
NETWORKID=
EXTRAPORTS=
REPO="https://raw.githubusercontent.com/jota-equis/nodes/main";
# · ---
echo -e "| CLOUD-FINISH ... :: start :: ..."
# · ---
usermod -L root;
echo "root:$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)" | chpasswd;
usermod -U root;

mkdir -pm0751 /srv/{backup,data,local} /var/lib/{docker,longhorn,rancher} /mnt/tmp;
mkdir -pm0751 /srv/local/{bin,etc/.env}; chmod 0710 /srv/local/etc/.env; 

curl -o /etc/apt/apt.conf.d/999-local ${REPO}/node/config/etc/apt/apt.conf.d/999-local;
curl -o /etc/fail2ban/jail.d/sshd.conf ${REPO}/node/config/etc/fail2ban/jail.d/sshd.conf;
curl -o /etc/fail2ban/jail.d/portscan.conf ${REPO}/node/config/etc/fail2ban/jail.d/portscan.conf;
curl -o /etc/ssh/sshd_config ${REPO}/node/config/etc/ssh/sshd_config && chmod 0600 /etc/ssh/sshd_config;
curl -o /etc/sysctl.d/999-local.conf ${REPO}/node/config/etc/sysctl.d/999-local.conf;
curl -o /etc/systemd/timesyncd.conf ${REPO}/node/config/etc/systemd/timesyncd.conf;
curl -o /srv/local/bin/local-ifaces.sh ${REPO}/node/config/bin/local-ifaces.sh;
curl -o /srv/local/bin/local-netplan.sh ${REPO}/node/config/bin/local-netplan.sh;
curl -o /srv/local/etc/netplan-local.yaml ${REPO}/node/config/etc/netplan/99-local.yaml;

for I in EXTRAPORTS DOMAIN MASTER REPO ROLE SSH_PORT SYS_LANG TOKEN NETWORKID; do [[ -z "${!I}" ]] && touch "/srv/local/etc/.env/${I}" || echo "${!I}" > "/srv/local/etc/.env/${I}"; done

chmod 0600 /srv/local/etc/.env/*;
chmod 0750 /srv/local/bin/*;

/srv/local/bin/local-ifaces.sh;

if [[ "x${SSH_PORT}" != "x22" ]]; then
    sed -i "s/^Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config;
    sed -i '/^Port ${SSH_PORT}/a Port 22' /etc/ssh/sshd_config;
    sed -i "s/Port 22/Port ${SSH_PORT}/" /etc/ssh/ssh_config;
    sed -i "s/^port = 22$/&,${SSH_PORT}/" /etc/fail2ban/jail.d/sshd.conf;
fi

[[ ! -z "${DOMAIN}" ]] && sed -i "s/^#kernel.domainname/kernel.domainname           = ${DOMAIN}/g" /etc/sysctl.d/999-local.conf;

echo -e "\n[[ -f /etc/bash_completion ]] && ! shopt -oq posix && . /etc/bash_completion\n" >> /root/.bashrc;
sed -i 's/^#force_color_prompt/force_color_prompt/g' /etc/skel/.bashrc;
sed -i 's/^#force_color_prompt/force_color_prompt/g' /root/.bashrc;
sed -i 's/^#ReadEtcHosts/ReadEtcHosts/g' /etc/systemd/resolved.conf;
sed 's/^Options=/Options=noexec,/g' /usr/share/systemd/tmp.mount > /etc/systemd/system/tmp.mount;

localectl set-locale LANG=${SYS_LANG}.UTF-8 LANGUAGE=${SYS_LANG} LC_MESSAGES=POSIX LC_COLLATE=C;

rm -Rf /tmp/* /tmp/.*;

systemctl enable tmp.mount && systemctl start tmp.mount;
systemctl restart systemd-timesyncd.service;
systemctl enable fail2ban;

for d in $(lsblk -dnoNAME | grep sd); do
  echo -e "\nblock/${d}/queue/iosched/front_merges = 0" > /etc/sysfs.d/${d}.conf;
  echo "block/${d}/queue/iosched/read_expire = 150" >> /etc/sysfs.d/${d}.conf;
  echo "block/${d}/queue/iosched/write_expire = 1500" >> /etc/sysfs.d/${d}.conf;
done

echo rbd >> /etc/modules;
echo iscsi_tcp >> /etc/modules;

echo "17 3 */2 * *      root    /usr/sbin/fstrim --all" > /etc/cron.d/fstrim;
chmod 0751 /etc/cron.d/fstrim;
# · ---
DEBIAN_FRONTEND=noninteractive apt -y full-upgrade && apt -y autoclean && apt -y autoremove && sync;
fstrim --all;
# · ---
echo -e "| CLOUD-FINISH ... :: end :: ..."
# · ---
exit 0
