#########################################KEYSTONE#########################################
apt -y install mariadb-server rabbitmq-server memcached python3-pymysql
systemctl restart mariadb

---------------------------------------------------
mysql_secure_installation
Enter current password for root (enter for none):
Switch to unix_socket authentication [Y/n] n
Change the root password? [Y/n] n
Remove anonymous users? [Y/n] y
Disallow root login remotely? [Y/n] y
Remove test database and access to it? [Y/n] y
Reload privilege tables now? [Y/n] y
---------------------------------------------------

rabbitmqctl add_user openstack password
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
cp /etc/mysql/mariadb.conf.d/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf.bak
cp /etc/memcached.conf /etc/memcached.conf.bak

---------------------------------------------------
root@dlp:~# vi /etc/mysql/mariadb.conf.d/50-server.cnf
# line 30 : change
bind-address = 0.0.0.0
# line 43 : uncomment and change
# default value 151 is not enough on Openstack Env
max_connections = 500
---------------------------------------------------

---------------------------------------------------
root@dlp:~# vi /etc/memcached.conf
# line 35 : change
-l 0.0.0.0
---------------------------------------------------

systemctl restart mariadb rabbitmq-server memcached
systemctl enable mariadb rabbitmq-server memcached

---------------------------------------------------
root@dlp:~# mysql
MariaDB [(none)]> create database keystone; grant all privileges on keystone.* to keystone@'localhost' identified by 'password'; grant all privileges on keystone.* to keystone@'%' identified by 'password'; flush privileges; 
MariaDB [(none)]> exit
Bye
---------------------------------------------------

apt -y install keystone python3-openstackclient apache2 libapache2-mod-wsgi-py3 python3-oauth2client
cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.bak

---------------------------------------------------
root@dlp:~# vi /etc/keystone/keystone.conf
# line 360 : add Memcache Server info
memcache_servers = 10.26.15.224:11211
# line 506 : add MariaDB connection info
connection = mysql+pymysql://keystone:password@10.26.15.224/keystone
# line 2069 : uncomment
provider = fernet
---------------------------------------------------

su -s /bin/bash keystone -c "keystone-manage db_sync"
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password adminpassword --bootstrap-admin-url http://10.26.15.224:5000/v3/ --bootstrap-internal-url http://10.26.15.224:5000/v3/ --bootstrap-public-url http://10.26.15.224:5000/v3/ --bootstrap-region-id RegionOne
cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf.bak
echo "ServerName 10.26.15.224" >> /etc/apache2/apache2.conf
systemctl restart apache2

---------------------------------------------------
root@dlp:~# vi ~/keystonerc
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=admin
export OS_PASSWORD=adminpassword
export OS_AUTH_URL=http://10.26.15.224:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
export PS1='\u@\h \W(keystone)\$ '
---------------------------------------------------

chmod 600 ~/keystonerc; source ~/keystonerc

root@dlp ~(keystone)# echo "source ~/keystonerc " >> ~/.bashrc
openstack project create --domain default --description "Service Project" service
openstack project list


#########################################GLANCE#########################################
root@dlp ~(keystone)# 

openstack user create --domain default --project service --password servicepassword glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint create --region RegionOne image public http://10.26.15.224:9292
openstack endpoint create --region RegionOne image internal http://10.26.15.224:9292
openstack endpoint create --region RegionOne image admin http://10.26.15.224:9292


---------------------------------------------------
root@dlp ~(keystone)# mysql
MariaDB [(none)]> create database glance; grant all privileges on glance.* to glance@'localhost' identified by 'password'; grant all privileges on glance.* to glance@'%' identified by 'password'; flush privileges; 
MariaDB [(none)]> exit
Bye
---------------------------------------------------

apt -y install glance
mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.bak

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/glance/glance-api.conf
# create new
[DEFAULT]
bind_host = 0.0.0.0

[glance_store]
stores = file,http
default_store = file
filesystem_store_datadir = /var/lib/glance/images/

[database]
# MariaDB connection info
connection = mysql+pymysql://glance:password@10.26.15.224/glance

# keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.26.15.224:5000
auth_url = http://10.26.15.224:5000
memcached_servers = 10.26.15.224:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = glance
password = servicepassword

[paste_deploy]
flavor = keystone
---------------------------------------------------

chmod 640 /etc/glance/glance-api.conf
chown root:glance /etc/glance/glance-api.conf
su -s /bin/bash glance -c "glance-manage db_sync"
systemctl restart glance-api
systemctl enable glance-api
wget https://cdimage.debian.org/cdimage/openstack/current-10/debian-10-openstack-amd64.qcow2 -P /var/kvm/images
apt install libguestfs-tools -y
virt-customize -a /var/kvm/images/debian-10-openstack-amd64.qcow2 --root-password password:123
openstack image create "Debian10" --file /var/kvm/images/debian-10-openstack-amd64.qcow2 --disk-format qcow2 --public
openstack image list


#########################################NOVA#########################################
openstack user create --domain default --project service --password servicepassword nova
openstack role add --project service --user nova admin
openstack user create --domain default --project service --password servicepassword placement
openstack role add --project service --user placement admin
openstack service create --name nova --description "OpenStack Compute service" compute
openstack service create --name placement --description "OpenStack Compute Placement service" placement
openstack endpoint create --region RegionOne compute public http://10.26.15.224:8774/v2.1/%\(tenant_id\)s
openstack endpoint create --region RegionOne compute internal http://10.26.15.224:8774/v2.1/%\(tenant_id\)s
openstack endpoint create --region RegionOne compute admin http://10.26.15.224:8774/v2.1/%\(tenant_id\)s
openstack endpoint create --region RegionOne placement public http://10.26.15.224:8778
openstack endpoint create --region RegionOne placement internal http://10.26.15.224:8778
openstack endpoint create --region RegionOne placement admin http://10.26.15.224:8778

---------------------------------------------------
root@dlp ~(keystone)# mysql
MariaDB [(none)]> create database nova; grant all privileges on nova.* to nova@'localhost' identified by 'password'; grant all privileges on nova.* to nova@'%' identified by 'password'; 
MariaDB [(none)]> create database nova_api; grant all privileges on nova_api.* to nova@'localhost' identified by 'password'; grant all privileges on nova_api.* to nova@'%' identified by 'password'; 
MariaDB [(none)]> create database placement; grant all privileges on placement.* to placement@'localhost' identified by 'password'; grant all privileges on placement.* to placement@'%' identified by 'password'; 
MariaDB [(none)]> create database nova_cell0; grant all privileges on nova_cell0.* to nova@'localhost' identified by 'password'; grant all privileges on nova_cell0.* to nova@'%' identified by 'password'; flush privileges; 
MariaDB [(none)]> exit
Bye
---------------------------------------------------

apt -y install nova-api nova-conductor nova-scheduler nova-novncproxy placement-api python3-novaclient
mv /etc/nova/nova.conf /etc/nova/nova.conf.bak

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/nova/nova.conf
# create new
[DEFAULT]
# define own IP address
my_ip = 10.26.15.224
state_path = /var/lib/nova
enabled_apis = osapi_compute,metadata
log_dir = /var/log/nova
# RabbitMQ connection info
transport_url = rabbit://openstack:password@10.26.15.224

[api]
auth_strategy = keystone

# Glance connection info
[glance]
api_servers = http://10.26.15.224:9292

[oslo_concurrency]
lock_path = $state_path/tmp

# MariaDB connection info
[api_database]
connection = mysql+pymysql://nova:password@10.26.15.224/nova_api

[database]
connection = mysql+pymysql://nova:password@10.26.15.224/nova

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.26.15.224:5000
auth_url = http://10.26.15.224:5000
memcached_servers = 10.26.15.224:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = nova
password = servicepassword

[placement]
auth_url = http://10.26.15.224:5000
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
mv /etc/placement/placement.conf /etc/placement/placement.conf.bak

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/placement/placement.conf
# create new
[DEFAULT]
debug = false

[api]
auth_strategy = keystone

[keystone_authtoken]
www_authenticate_uri = http://10.26.15.224:5000
auth_url = http://10.26.15.224:5000
memcached_servers = 10.26.15.224:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = placement
password = servicepassword

[placement_database]
connection = mysql+pymysql://placement:password@10.26.15.224/placement
---------------------------------------------------

chmod 640 /etc/placement/placement.conf
chgrp placement /etc/placement/placement.conf
su -s /bin/bash placement -c "placement-manage db sync"
su -s /bin/bash nova -c "nova-manage api_db sync"
su -s /bin/bash nova -c "nova-manage cell_v2 map_cell0"
su -s /bin/bash nova -c "nova-manage db sync"
su -s /bin/bash nova -c "nova-manage cell_v2 create_cell --name cell1"
systemctl restart apache2 nova-api nova-conductor nova-scheduler
systemctl enable apache2 nova-api nova-conductor nova-scheduler 
openstack compute service list


apt -y install qemu-kvm libvirt-daemon-system libvirt-daemon virtinst bridge-utils libosinfo-bin nova-compute nova-compute-kvm qemu-system-data

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

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/nova/nova.conf
# add follows (enable VNC)
[vnc]
enabled = True
server_listen = 0.0.0.0
server_proxyclient_address = 10.26.15.224
novncproxy_base_url = http://10.26.15.224:6080/vnc_auto.html 
---------------------------------------------------


---------------------------------------------------
root@dlp ~(keystone)# vi /etc/default/nova-consoleproxy
# line 6 : change
NOVA_CONSOLE_PROXY_TYPE=novnc
---------------------------------------------------

systemctl restart nova-compute nova-novncproxy
systemctl enable nova-compute nova-novncproxy
su -s /bin/bash nova -c "nova-manage cell_v2 discover_hosts"
openstack compute service list


#########################################NEUTRON#########################################
openstack user create --domain default --project service --password servicepassword neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking service" network
openstack endpoint create --region RegionOne network public http://10.26.15.224:9696
openstack endpoint create --region RegionOne network internal http://10.26.15.224:9696
openstack endpoint create --region RegionOne network admin http://10.26.15.224:9696

---------------------------------------------------
root@dlp ~(keystone)# mysql
MariaDB [(none)]> create database neutron_ml2; grant all privileges on neutron_ml2.* to neutron@'localhost' identified by 'password'; grant all privileges on neutron_ml2.* to neutron@'%' identified by 'password'; flush privileges; 
MariaDB [(none)]> exit 
Bye
---------------------------------------------------

apt -y install neutron-server neutron-plugin-ml2 neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent python3-neutronclient

mv /etc/neutron/neutron.conf /etc/neutron/neutron.conf.bak


---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/neutron.conf
# create new
[DEFAULT]
core_plugin = ml2
service_plugins = router
auth_strategy = keystone
state_path = /var/lib/neutron
dhcp_agent_notification = True
allow_overlapping_ips = True
notify_nova_on_port_status_changes = True
notify_nova_on_port_data_changes = True
# RabbitMQ connection info
transport_url = rabbit://openstack:password@10.26.15.224

[agent]
root_helper = sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf

# Keystone auth info
[keystone_authtoken]
www_authenticate_uri = http://10.26.15.224:5000
auth_url = http://10.26.15.224:5000
memcached_servers = 10.26.15.224:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = neutron
password = servicepassword

# MariaDB connection info
[database]
connection = mysql+pymysql://neutron:password@10.26.15.224/neutron_ml2

# Nova connection info
[nova]
auth_url = http://10.26.15.224:5000
auth_type = password
project_domain_name = default
user_domain_name = default
region_name = RegionOne
project_name = service
username = nova
password = servicepassword

[oslo_concurrency]
lock_path = $state_path/tmp
---------------------------------------------------

chmod 640 /etc/neutron/neutron.conf; chgrp neutron /etc/neutron/neutron.conf

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/metadata_agent.ini
# line 20 : uncomment and specify Nova API server
nova_metadata_host = 10.26.15.224
# line 30 : uncomment and specify any secret key you like
metadata_proxy_shared_secret = metadata_secret
# line 261 : add to specify Memcache Server
memcache_servers = 10.26.15.224:11211
---------------------------------------------------

root@allinone ~(keystone)# ovs-vsctl add-br br-ex; ovs-vsctl add-port br-ex enp0s31f6

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/plugins/ml2/ml2_conf.ini
[ml2]
type_drivers = local,flat,vlan
tenant_network_types = local,flat,vlan
mechanism_drivers = openvswitch,l2population

[ml2_type_flat]
flat_networks = external

---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/neutron/plugins/ml2/openvswitch_agent.ini
[ovs]
local_ip = 10.26.15.224
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
root@dlp ~(keystone)# vi /etc/nova/nova.conf
# add follows into [DEFAULT] section
use_neutron = True
vif_plugging_is_fatal = True
vif_plugging_timeout = 300

# add follows to the end : Neutron auth info
# the value of [metadata_proxy_shared_secret] is the same with the one in [metadata_agent.ini]
[neutron]
auth_url = http://10.26.15.224:5000
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
su -s /bin/bash neutron -c "neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugin.ini upgrade head"
systemctl restart neutron-api neutron-rpc-server neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent neutron-openvswitch-agent nova-api nova-compute
systemctl enable neutron-api neutron-rpc-server neutron-l3-agent neutron-dhcp-agent neutron-metadata-agent neutron-openvswitch-agent nova-api nova-compute
openstack network agent list 
(Note: You need to wait for a while until all the agents are up)

#########################################Security Group, Flavor#########################################
openstack security group create secgroup01
openstack security group list
ssh-keygen -q -N ""
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
openstack keypair list

openstack project create --domain default --description "Hiroshima Project" hiroshima
openstack user create --domain default --project hiroshima --password userpassword serverworld
openstack role create CloudUser
openstack role add --project hiroshima --user serverworld CloudUser
openstack flavor create --id 0 --vcpus 1 --ram 2048 --disk 10 m1.small


#########################################Horizon#########################################
apt -y install openstack-dashboard

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/openstack-dashboard/local_settings.py
# line 40 : specify allowed compute hosts to connect to horizon
ALLOWED_HOSTS = ['*']
# line 107 : add
SESSION_ENGINE = "django.contrib.sessions.backends.cache"
# line 120 : set Openstack Host
# line 121 : comment out and add a line to specify URL of Keystone Host
OPENSTACK_HOST = "10.26.15.224"
OPENSTACK_KEYSTONE_URL = "http://10.26.15.224:5000/v3"
---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/openstack-dashboard/local_settings.d/_0006_debian_cache.py
# change to your Memcache server
CACHES = {
  'default' : {
    'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
    'LOCATION': '10.26.15.224:11211',
  }
}
---------------------------------------------------

---------------------------------------------------
root@dlp ~(keystone)# vi /etc/apache2/conf-available/openstack-dashboard.conf
# create new
WSGIScriptAlias / /usr/share/openstack-dashboard/wsgi.py process-group=horizon
WSGIDaemonProcess horizon user=horizon group=horizon processes=3 threads=10 display-name=%{GROUP}
WSGIProcessGroup horizon
WSGIApplicationGroup %{GLOBAL}

Alias /static /var/lib/openstack-dashboard/static/
Alias /horizon/static /var/lib/openstack-dashboard/static/

<Directory /usr/share/openstack-dashboard>
  Require all granted
</Directory>

<Directory /var/lib/openstack-dashboard/static>
  Require all granted
</Directory>
---------------------------------------------------

a2enconf openstack-dashboard; systemctl reload apache2; a2enconf openstack-dashboard
mv /etc/openstack-dashboard/policy /etc/openstack-dashboard/policy.bak
chown -R horizon /var/lib/openstack-dashboard/secret-key
systemctl restart apache2

#########################################Others#########################################
Create Networks, Instances through the Horizon WEB UI