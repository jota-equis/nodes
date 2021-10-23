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

mkdir -pm0751 /srv/{backup,data,local} /var/lib/{docker,longhorn,rancher} /mnt/{storage,tmp};
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
curl -o /srv/local/etc/.my_kuberc ${REPO}/node/config/etc/.my_kuberc;

chmod 0644 /srv/local/etc/.my_kuberc;

[[ -f /etc/environment ]] && . /etc/environment;

[[ ! -z $THIS_ROLE ]] && ROLE="$THIS_ROLE";
[[ ! -z $THIS_DOMAIN ]] && DOMAIN="$THIS_DOMAIN";
[[ ! -z $THIS_LOCAL_DOMAIN ]] && LOCAL_DOMAIN="$THIS_LOCAL_DOMAIN";
[[ ! -z $THIS_SSH_PORT ]] && SSH_PORT="$THIS_SSH_PORT" || SSH_PORT=22;
[[ ! -z $THIS_HTTP_PORT ]] && HTTP_PORT="$THIS_HTTP_PORT" || HTTP_PORT=80;
[[ ! -z $THIS_HTTPS_PORT ]] && HTTPS_PORT="$THIS_HTTPS_PORT" || HTTPS_PORT=443;
[[ ! -z $THIS_LOCAL_CIDR ]] && LOCAL_CIDR="$THIS_LOCAL_CIDR";
[[ ! -z $THIS_PODS_CIDR ]] && PODS_CIDR="$THIS_PODS_CIDR" || PODS_CIDR="10.42.0.0/16";
[[ ! -z $THIS_SVC_CIDR ]] && SVC_CIDR="$THIS_SVC_CIDR" || SVC_CIDR="10.43.0.0/16";
[[ ! -z $THIS_TOKEN ]] && TOKEN="$THIS_TOKEN";
[[ ! -z $THIS_TOKENCSI ]] && TOKENCSI="$THIS_TOKENCSI";
[[ ! -z $THIS_NETWORKID ]] && NETWORKID="$THIS_NETWORKID";
[[ ! -z $THIS_LBZONE ]] && LBZONE="$THIS_LBZONE";
[[ ! -z $THIS_RANCHERIP ]] && RKE_IP="$THIS_RANCHERIP";
[[ ! -z $THIS_FIXED_IPLAN ]] && THIS_FIXED_IPLAN="$THIS_FIXED_IPLAN";
[[ ! -z $THIS_LABELS ]] && LABELS="$THIS_LABELS";

echo "" > /etc/environment;

for I in EXTRAPORTS DOMAIN MASTER REPO ROLE SSH_PORT SYS_LANG TOKEN TOKENCSI NETWORKID LABELS LBZONE LOCAL_CIDR PODS_CIDR SVC_CIDR RKE_IP HTTP_PORT HTTPS_PORT; do
    [[ -z "${!I}" ]] && touch "/srv/local/etc/.env/${I}" || echo "${!I}" > "/srv/local/etc/.env/${I}";
done

chmod 0600 /srv/local/etc/.env/*;
chmod 0750 /srv/local/bin/*;

if [[ "x${THIS_FIXED_IPLAN}" = "x1" ]]; then
    apt install -y ifupdown net-tools;
    
    sed -i -e 's/^GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"/' /etc/default/grub;
    update-grub;
    
    mkdir -pm0755 /etc/network/interfaces.d;

    cat << EOF > /etc/network/interfaces
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto eth0
auto eth1

dns-nameservers 1.1.1.1 8.8.8.8
EOF

    ETH0_IP=$(ip -4 -f inet a show eth0 | awk '/inet/{ print $2 }' | awk -F "/" '{ print $1 }');

    cat << EOF > /etc/network/interfaces.d/60-public-network.cfg
iface eth0 inet static
    address $ETH0_IP
    netmask 255.255.255.255
    gateway 172.31.1.1
    pointopoint 172.31.1.1
    dns-nameservers 1.1.1.1 8.8.8.8

#iface eth0 inet6 static
#    address <2001:db8:0:3df1::1>
#    netmask 64
#    gateway fe80::1
EOF

    ETH1_DEV=$(find /sys/class/net -type l -not -name eth0 -not -lname '*virtual*' -printf '%f ' | tr " " "\n" | sort);
    ETH1_IP=$(ip -4 -f inet a show $ETH1_DEV | awk '/inet/{ print $2 }' | awk -F "/" '{ print $1 }');
    ETH1_GW=$(ip -4 r list dev $ETH1_DEV scope link);

    [[ ! -z $LOCAL_CIDR ]] && ETH1_NT="$LOCAL_CIDR" || ETH1_NT=$(ip -4 r list dev $ETH1_DEV via $ETH1_GW);

    cat << EOF > /etc/network/interfaces.d/61-my-private-network.cfg
iface eth1 inet static
    address $ETH1_IP
    netmask 255.255.255.255
    mtu 1450
    pointopoint $ETH1_GW
    post-up ip route add $ETH1_NT via $ETH1_GW dev eth1
EOF

    echo -e "network:\n  config: disabled\n" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg;
    rm -f /etc/network/interfaces.d/50-cloud-init.cfg /etc/netplan/50-cloud-init.yaml;
fi

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

if [[ ! -z "${LOCAL_CIDR}" ]]; then
    ufw allow from "$LOCAL_CIDR" comment "Private subnet";
    ufw allow from "$PODS_CIDR" comment "K8s Pods CIDR";
    ufw allow from "$SVC_CIDR" comment "K8s Services CIDR";
fi

if [[ "x${ROLE}" = "xrancher" ]]; then
    ufw allow ${HTTP_PORT}/tcp comment "Rancher http";
    ufw allow ${HTTPS_PORT}/tcp comment "Rancher https";
else
    if [[ "x${RKE_IP}" != "x" ]]; then
        sed -i "s|^Match Address 127\.0.*|&,${RKE_IP}|" /etc/ssh/sshd_config;
        ufw allow from ${RKE_IP} comment "Rancher";
    fi

    if [[ "x${ROLE}" != "xmaster" ]]; then
        mkdir -pm0755 /mnt/huge;
        echo iscsi_tcp >> /etc/modules;
        tuned-adm profile network-latency;

        ufw allow ${HTTP_PORT}/tcp comment "Worker http";
        ufw allow ${HTTPS_PORT}/tcp comment "Worker https";

        mkdir -pm0750 /srv/data/rke2 /etc/rancher/rke2;
        touch /srv/data/rke2/config.yaml && chmod 0640 /srv/data/rke2/config.yaml;
        ln -sf /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml;

        curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
    else
        cd ~;
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3;
        chmod 0700 get_helm.sh;
        ./get_helm.sh && sleep 1 && rm -f get_helm.sh;

        mkdir -pm0750 /srv/data/rke2 /etc/rancher/rke2 /var/lib/rancher/rke2/server/manifests;

        touch /srv/data/rke2/config.yaml /srv/data/rke2/rke2-cilium-config.yaml \
          /srv/data/rke2/rke2-coredns-config.yaml;

        chmod 0640 /srv/data/rke2/*.yaml;
        ln -sf /var/lib/rancher/rke2/agent/etc/crictl.yaml /etc/crictl.yaml;

        curl -sfL https://get.rke2.io | sh -
    fi
fi

if [[ ! -z "${DOMAIN}" ]]; then
    sed -i "s/^#kernel.domainname/kernel.domainname           = ${DOMAIN}/g" /etc/sysctl.d/999-local.conf;
fi

if [[ ! -z "${LOCAL_DOMAIN}" ]]; then
    sed -i "s/^127.0.1.1 $HOSTNAME $HOSTNAME$/127.0.1.1 $HOSTNAME.$LOCAL_DOMAIN $HOSTNAME/" /etc/hosts;
fi

[[ -f /etc/hosts.localnet ]] && sed -i '/^127.0.0.1 localhost$/r'<(cat /etc/hosts.localnet) /etc/hosts;

if [[ ! -z $THIS_IPV6 && "x$THIS_IPV6" = "x1"  ]]; then
    sed -i 's/^net.ipv6/# net.ipv6/g' /etc/sysctl.d/999-local.conf;
else
    for i in $(ufw status numbered  | awk '/(v6)/ { gsub("^[[]+",""); gsub("[]]",""); print $1 }' | sort -r); do
        yes | ufw delete ${i};
    done
fi

echo -e "\n[[ -f /etc/bash_completion ]] && ! shopt -oq posix && . /etc/bash_completion\n" >> /root/.bashrc;
sed -i 's/^#force_color_prompt/force_color_prompt/g' /etc/skel/.bashrc;
sed -i 's/^#force_color_prompt/force_color_prompt/g' /root/.bashrc;
sed 's/^Options=/Options=noexec,/g' /usr/share/systemd/tmp.mount > /etc/systemd/system/tmp.mount;

echo -e "\nnone\t\t/sys/fs/bpf\tbpf\trw,relatime\t\t0\t0\n" >> /etc/fstab;

localectl set-locale LANG=${SYS_LANG}.UTF-8 LANGUAGE=${SYS_LANG} LC_MESSAGES=POSIX LC_COLLATE=C;

rm -Rf /tmp/* /tmp/.* /etc/resolv.conf;

cat << 'EOF' > /etc/systemd/resolved.conf
[Resolve]
DNS=1.1.1.1 8.8.8.8 2606:4700:4700::1111
DNSStubListener=No
ReadEtcHosts=yes
EOF

cat << 'EOF' > /etc/resolv.conf
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 2606:4700:4700::1111
EOF

# echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/999-local.conf;
echo "net.ipv4.conf.lxc*.rp_filter = 0" >> /etc/sysctl.d/999-local.conf;

sysctl --system;

systemctl disable systemd-resolved --now;
systemctl enable tmp.mount --now;
systemctl restart systemd-timesyncd.service;
systemctl enable fail2ban;

for d in $(lsblk -dnoNAME | grep sd); do
  echo -e "\nblock/${d}/queue/iosched/front_merges = 0" > /etc/sysfs.d/${d}.conf;
  echo "block/${d}/queue/iosched/read_expire = 150" >> /etc/sysfs.d/${d}.conf;
  echo "block/${d}/queue/iosched/write_expire = 1500" >> /etc/sysfs.d/${d}.conf;
done

echo rbd >> /etc/modules;
echo "SELECTED_EDITOR=\"/bin/nano\"" > /root/.selected_editor;

echo "17 3 */2 * *      root    /usr/sbin/fstrim --all" > /etc/cron.d/fstrim;
chmod 0751 /etc/cron.d/fstrim;
# · ---
DEBIAN_FRONTEND=noninteractive apt -y full-upgrade && apt -y autoclean && apt -y autoremove && sync;
fstrim --all;
# · ---
echo -e "| CLOUD-FINISH ... :: end :: ..."
# · ---
exit 0
