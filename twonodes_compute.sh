#########################################NOVA-Compute#########################################
apt -y install qemu-kvm libvirt-daemon-system libvirt-daemon virtinst bridge-utils libosinfo-bin
apt -y install nova-compute nova-compute-kvm qemu-system-data

---------------------------------------------------
root@node01:~# vi /etc/default/grub
# line 10 : add
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=false systemd.legacy_systemd_cgroup_controller=false"
---------------------------------------------------

update-grub
reboot

mv /etc/nova/nova.conf /etc/nova/nova.conf.bak

---------------------------------------------------
root@node01:~# vi /etc/nova/nova.conf
# create new
[DEFAULT]
# define own IP address
my_ip = 10.26.15.223
state_path = /var/lib/nova
enabled_apis = osapi_compute,metadata
log_dir = /var/log/nova
# RabbitMQ connection info
transport_url = rabbit://openstack:password@10.26.15.222

[api]
auth_strategy = keystone

# enable VNC
[vnc]
enabled = True
server_listen = 0.0.0.0
server_proxyclient_address = 10.26.15.223
novncproxy_base_url = http://10.26.15.223:6080/vnc_auto.html

# Glance connection info
[glance]
api_servers = http://10.26.15.222:9292

[oslo_concurrency]
lock_path = $state_path/tmp

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.26.15.222:5000
auth_url = http://10.26.15.222:5000
memcached_servers = 10.26.15.222:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = servicepassword

[placement]
auth_url = http://10.26.15.222:5000
os_region_name = RegionOne
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = placement
password = servicepassword

[wsgi]
api_paste_config = /etc/nova/api-paste.ini
---------------------------------------------------

chmod 640 /etc/nova/nova.conf
chgrp nova /etc/nova/nova.conf
systemctl restart nova-compute
systemctl enable nova-compute



#########################################Neutron-Compute#########################################
apt -y install neutron-common neutron-plugin-ml2 neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent python3-neutronclient
mv /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak

---------------------------------------------------
vi /etc/neutron/neutron.conf
# create new
[DEFAULT]
core_plugin = ml2
service_plugins = router
auth_strategy = keystone
state_path = /var/lib/neutron
allow_overlapping_ips = True
# RabbitMQ connection info
transport_url = rabbit://openstack:password@10.26.15.222

[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.26.15.222:5000
auth_url = http://10.26.15.222:5000
memcached_servers = 10.26.15.222:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = servicepassword

[oslo_concurrency]
lock_path = $state_path/lock
---------------------------------------------------

chmod 640 /etc/neutron/neutron.conf
chgrp neutron /etc/neutron/neutron.conf
cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.bak
cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.bak
cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.bak
cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.bak
cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.bak

---------------------------------------------------
root@node01:~# vi /etc/neutron/metadata_agent.ini
# line 20 : uncomment and specify Nova API server
nova_metadata_host = 10.26.15.222
# line 30 : uncomment and specify any secret-words you like
metadata_proxy_shared_secret = metadata_secret
# line 261 : add to specify Memcache server
memcache_servers = 10.26.15.222:11211
---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/plugins/ml2/ml2_conf.ini
[ml2]
type_drivers = local,flat,vlan
tenant_network_types = local,flat,vlan
mechanism_drivers = openvswitch,l2population

[ml2_type_flat]
flat_networks = external
---------------------------------------------------

root@compute ~(keystone)# ovs-vsctl add-br br-ex; ovs-vsctl add-port br-ex enp0s31f6
---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
local_ip = 10.26.15.223
bridge_mappings = external:br-ex
---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/l3_agent.ini
[DEFAULT]
ovs_use_veth = True
interface_driver = openvswitch
---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/dhcp_agent.ini
# line 18 : change
interface_driver = openvswitch
# line 37 : uncomment
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
---------------------------------------------------

---------------------------------------------------
root@node01:~# vi /etc/nova/nova.conf
# add follows into [DEFAULT] section
use_neutron = True
vif_plugging_is_fatal = True
vif_plugging_timeout = 300
# add follows to the end: Neutron auth info
# the value of [metadata_proxy_shared_secret] is the same with the one in [metadata_agent.ini]
[neutron]
auth_url = http://10.26.15.222:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = neutron
password = servicepassword
service_metadata_proxy = True
metadata_proxy_shared_secret = metadata_secret
---------------------------------------------------

ln -s /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugin.ini
systemctl restart nova-compute neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent
systemctl enable nova-compute neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent