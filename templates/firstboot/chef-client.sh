#!/bin/bash

### BEGIN INIT INFO
# Provides:          firstboot
# Required-Start:    $local_fs $network $syslog
# Required-Stop:     $local_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Firstboot actions
# Description:       Firstboot actions
### END INIT INFO

# Enable debug output and exit on error
set -e
set -x

sleep 10

sed -i /etc/rc.local -e 's_/root/install.sh_exit 0_'

if [ -t 1 ]; then
    exec >/tmp/firstboot.log
    exec 2>&1
fi

# Check if we have network access before continuing
until ping -q -w 1 -c 1 `ip r | grep default | cut -d ' ' -f 3` > /dev/null; do
  sleep 5
done

{% if host.use_openvswitch %}
# Install and configure OVS
apt-get update -qq
apt-get install -y openvswitch-switch openvswitch-common openvswitch-datapath-dkms dkms
# Workaround bug https://bugs.launchpad.net/ubuntu/+source/openvswitch/+bug/1084028
if [ ! -f /etc/init/openvswitch-switch.conf ]; then
  wget -nv -O /etc/init/openvswitch-switch.conf https://launchpadlibrarian.net/140036861/openvswitch-switch.upstart
  ln -fs /lib/init/upstart-job /etc/init.d/openvswitch-switch
fi

{% if host.utility_net_bond %}
# Take net-mgmt down
ip link set net-mgmt down
# Remove the bridge
brctl delbr net-mgmt
# Remove the bridge config
sed -i '/bridge_ports eth0/d' /etc/network/interfaces
{% endif %}

# Setup the OVS bridge
service openvswitch-switch start
sleep 10
ovs-vsctl add-br br-trunk0

{% if host.utility_net_bond %}
# Setup the bond
ovs-vsctl add-bond br-trunk0 bond0 {{host.utility_net_bond_interfaces}} lacp=active bond_mode=balance-tcp other_config:lacp_time=fast
{% endif %}

# Add the mgmt utility net
{% if host.utility_net_bond %}
ovs-vsctl add-port br-trunk0 net-mgmt tag={{site.net_mgmt_vlan}} -- set interface net-mgmt type=internal
ip link set net-mgmt up
{% endif %}

{% if host.utility_net_san and host.utility_net_bond %}
# Add the san utility net
ovs-vsctl add-port br-trunk0 net-san tag={{site.net_san_vlan}} -- set interface net-san type=internal
cat >>/etc/network/interfaces <<EOF

auto net-san
iface net-san inet static
  address {{host.utility_net_san_address}}
  netmask {{host.utility_net_san_netmask}}
EOF
ip link set net-san up
{% endif %}

{% if host.utility_net_gre and host.utility_net_bond %}
# Add the gre utility net
ovs-vsctl add-port br-trunk0 net-gre tag={{site.net_gre_vlan}} -- set interface net-gre type=internal
cat >>/etc/network/interfaces <<EOF

auto net-gre
iface net-gre inet static
  address {{host.utility_net_gre_address}}
  netmask {{host.utility_net_gre_netmask}}
EOF
ip link set net-gre up
{% endif %}

{% else %}

{% if host.utility_net_san %}
# Add the san utility net
cat >>/etc/network/interfaces <<EOF

auto net-san
iface net-san inet static
  bridge_ports {{host.utility_net_san_interface}}
  address {{host.utility_net_san_address}}
  netmask {{host.utility_net_san_netmask}}
EOF
ip link set net-san up
{% endif %}

{% if host.utility_net_gre %}
# Add the gre utility net
cat >>/etc/network/interfaces <<EOF

auto net-gre
iface net-gre inet static
  bridge_ports {{host.utility_net_gre_interface}}
  address {{host.utility_net_gre_address}}
  netmask {{host.utility_net_gre_netmask}}
EOF
ip link set net-gre up
{% endif %}

{% endif %}

# Download and install the chef-client
if [ ! -f /usr/bin/chef-client ]; then
  {% if site.mirror_opscode %}
     package=`curl -s http://{{site.mirror_opscode}}/ | egrep -o ">chef_.*.deb<" | sed "s/^>\(.*\)<$/\1/" | sort -V | tail -1`
     wget -nv -P /tmp/ -nv -c http://{{site.mirror_opscode}}/${package}
     dpkg -i /tmp/${package}
  {% else %}
    bash < <(curl -s  http://www.opscode.com/chef/install.sh)
  {% endif %}
fi

# Create the required directories
mkdir -p /etc/chef /var/log/chef

# Create the chef client configuration
cat > /etc/chef/client.rb <<EOF
log_level	:info
log_location	STDOUT

chef_server_url	'{{ site.chef_server_url }}'
environment '{{ site.chef_environment }}'

{% if site.validation_client_name %}
    validation_client_name '{{ site.validation_client_name }}'
{% endif %}
{% if site.http_proxy %}
    http_proxy '{{ site.http_proxy|safe }}'
{% endif %}
{% if site.https_proxy %}
    https_proxy '{{ site.https_proxy|safe }}'
{% endif %}
{% if site.http_proxy_user %}
    http_proxy_user '{{ site.http_proxy_user|safe }}'
{% endif %}
{% if site.http_proxy_pass %}
    http_proxy_pass '{{ site.http_proxy_pass|safe }}'
{% endif %}
EOF

# Get the chef validator certificate
wget -O /etc/chef/validation.pem http://{{site.webservice_host}}:{{site.webservice_port}}/media/chef_validators/{{site.chef_validation_pem}}

# Configure chef-client upstart
cp /opt/chef/embedded/lib/ruby/gems/1.9.1/gems/chef-`dpkg-query --show chef | awk '{print $2}' | awk -F- '{print $1}'`/distro/debian/etc/init/chef-client.conf /etc/init/
ln -fs /lib/init/upstart-job /etc/init.d/chef-client

# If a role is assigned, use it
{% if host.role %}
cat > /etc/chef/firstboot.json <<EOF
{ "run_list":
    [
      "role[{{host.role}}]"
    ]
}
EOF
chef-client -j /etc/chef/firstboot.json
{% endif %}

# Start the chef-client service
service chef-client start
