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
LOCAL_CIDR=
THIS_IPV6=
RKE_IP=
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

[[ -f /etc/environment ]] && . /etc/environment;

[[ ! -z $THIS_ROLE ]] && ROLE="$THIS_ROLE";
[[ ! -z $THIS_DOMAIN ]] && DOMAIN="$THIS_DOMAIN";
[[ ! -z $THIS_SSH_PORT ]] && SSH_PORT="$THIS_SSH_PORT" || SSH_PORT=22;
[[ ! -z $THIS_LOCAL_CIDR ]] && LOCAL_CIDR="$THIS_LOCAL_CIDR";
[[ ! -z $THIS_TOKEN ]] && TOKEN="$THIS_TOKEN";
[[ ! -z $THIS_NETWORKID ]] && NETWORKID="$THIS_NETWORKID";
[[ ! -z $THIS_RANCHERIP ]] && RKE_IP="$THIS_RANCHERIP";
[[ ! -z $THIS_FIXED_IPLAN ]] && THIS_FIXED_IPLAN="$THIS_FIXED_IPLAN";

echo "" > /etc/environment;

for I in EXTRAPORTS DOMAIN MASTER REPO ROLE SSH_PORT SYS_LANG TOKEN NETWORKID LOCAL_CIDR RKE_IP; do [[ -z "${!I}" ]] && touch "/srv/local/etc/.env/${I}" || echo "${!I}" > "/srv/local/etc/.env/${I}"; done

chmod 0600 /srv/local/etc/.env/*;
chmod 0750 /srv/local/bin/*;

[[ ! -z "${THIS_FIXED_IPLAN}" && "x${THIS_FIXED_IPLAN}" = "x1" ]] && /srv/local/bin/local-ifaces.sh;

if [[ "x${SSH_PORT}" != "x22" ]]; then
    sed -i "s/^Port 22/Port ${SSH_PORT}/" /etc/ssh/sshd_config;
    sed -i "s/Port 22/Port ${SSH_PORT}/" /etc/ssh/ssh_config;
    sed -i "s/^port = 22$/&,${SSH_PORT}/" /etc/fail2ban/jail.d/sshd.conf;

    ufw limit $SSH_PORT/tcp comment "SSH admin access";
    
    if [[ ! -z $THIS_SSH_PORT_KEEP && "x$THIS_SSH_PORT_KEEP" = "x1" ]]; then
        sed -i "/^Port ${SSH_PORT}/a Port 22" /etc/ssh/sshd_config;
        ufw limit 22/tcp comment "SSH access";
    fi
else
    ufw limit 22/tcp comment "SSH access";
fi

if [[ "x${ROLE}" = "xrancher" ]]; then
    ufw allow 80/tcp comment "Rancher http";
    ufw allow 443/tcp comment "Rancher https";
else
    if [[ "x${RKE_IP}" != "x" ]]; then
        sed -i "s|^Match Address 127\.0.*|&,${RKE_IP}|" /etc/ssh/sshd_config;
        ufw allow from ${RKE_IP} comment "Rancher";
    fi

    if [[ "x${ROLE}" != "xmaster" ]]; then
        echo iscsi_tcp >> /etc/modules;
    fi
fi

if [[ ! -z "${DOMAIN}" ]]; then
    sed -i "s/^#kernel.domainname/kernel.domainname           = ${DOMAIN}/g" /etc/sysctl.d/999-local.conf;
    sed -i "s/^127.0.1.1 $HOSTNAME $HOSTNAME$/127.0.1.1 $HOSTNAME.$DOMAIN $HOSTNAME/" /etc/hosts;
fi

[[ -f /etc/hosts.localnet ]] && sed -i '/^127.0.0.1 localhost$/r'<(cat /etc/hosts.localnet) /etc/hosts;

[[ ! -z "${LOCAL_CIDR}" ]] && ufw allow from "$LOCAL_CIDR" comment "Private subnet";

if [[ ! -z $THIS_IPV6 && "x$THIS_IPV6" = "x1"  ]]; then
    sed -i 's/^net.ipv6/# net.ipv6/g' /etc/sysctl.d/999-local.conf;
else
    for i in $(ufw status numbered  | grep "(v6)" | awk '{ print $1 }' | sed 's/\[//' | sed 's/\]//' | sort -r); do
        yes | ufw delete ${i};
    done
fi

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

echo "$(echo 2 | select-editor | grep nano | awk '{ print ($0+0) }')" | select-editor;

echo "17 3 */2 * *      root    /usr/sbin/fstrim --all" > /etc/cron.d/fstrim;
chmod 0751 /etc/cron.d/fstrim;
# · ---
DEBIAN_FRONTEND=noninteractive apt -y full-upgrade && apt -y autoclean && apt -y autoremove && sync;
fstrim --all;
# · ---
echo -e "| CLOUD-FINISH ... :: end :: ..."
# · ---
exit 0
