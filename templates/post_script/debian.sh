#!/bin/bash

# Enable debug output and exit on error
set -e
set -x

# Fetch the firstboot script and set it to execute on next boot
curl -skS http://{{site.webservice_host}}:{{site.webservice_port}}/firstboot/{{host.id}} > /root/install.sh

if [ -s /root/install.sh ]; then
    chmod +x /root/install.sh
    sed -i /etc/rc.local -e 's_exit 0_/root/install.sh_'
fi

# Generate root's ssh keys
ssh-keygen -q -t rsa -N '' -f ~/.ssh/id_rsa

# Ensure that the hostname and hosts file are correctly configured
echo "{{host.hostname}}" > /etc/hostname
sed -i "s/127.0.1.1.*/{{host.ip_address}} {{host.hostname}}.{{site.domainname}} {{host.hostname}}/" /etc/hosts

# Setup all network interfaces
cat >/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback
EOF
for interface in `ip link show | grep -e " eth" | awk '{print $2}' | cut -d: -f 1`; do
cat >>/etc/network/interfaces <<EOF

auto ${interface}
iface ${interface} inet manual
  up ip link set \$IFACE up
  down ip link set \$IFACE down
EOF
done

# Add bridge-utils package
apt-get install -y bridge-utils

# Setup the management interface
cat >>/etc/network/interfaces <<EOF

auto net-mgmt
iface net-mgmt inet static
  bridge_ports eth0
  address {{host.ip_address}}
  netmask {{host.netmask}}
  gateway {{host.gateway}}
  dns-nameservers {{site.nameserver}}
  dns-search {{site.domainname}}
EOF

# Enable 'local boot' checkbox in DJeep and remove any existing Puppet Signature
curl http://{{site.webservice_host}}:{{site.webservice_port}}/api/host/{{host.id}} -H "Content-type: application/json" -d '{"local_boot": 1}' -X "PUT"
curl http://{{site.webservice_host}}:{{site.webservice_port}}/api/host/{{host.id}}/puppet_sig -X "DELETE"
