#!/bin/bash

#adsf

#Have a list of configuration here
#MASTERPUBIP = 123.41.15.3
#INTERNALNODENETWORK = 
# Also, the hosts too maybe?


#Disable selinux
#Add the EPEL repository

# Get repos in order


#############################################################################################################



#################################################
# Disable selinux

echo 0 > /selinux/enforce
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

#################################################
# Add EPEL and upgrade

rpm -i http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
yum -y upgrade

#################################################
# Setup cobbler

yum -y install cobbler httpd wget bind dhcp
sed -i 's/^server: 127.0.0.1/server: 10.69.0.1/g' /etc/cobbler/settings
sed -i 's/^client_use_localhost: 0/client_use_localhost: 1/g' /etc/cobbler/settings
sed -i 's/^manage_dns: 0/manage_dns: 1/g' /etc/cobbler/settings
sed -i 's|^manage_forward_zones: \[\]|manage_forward_zones: \[\x27vmcluster.local\x27\]|g' /etc/cobbler/settings
sed -i 's|^manage_reverse_zones: \[\]|manage_reverse_zones: \[\x2710.69\x27\]|g' /etc/cobbler/settings
sed -i 's|manage_dhcp: 0|manage_dhcp: 1|g' /etc/cobbler/settings
sed -i 's|^next_server: 127.0.0.1|next_server: 10.69.0.1|g' /etc/cobbler/settings
cat > /etc/cobbler/dhcp.template << EOF
ddns-update-style interim;

allow booting;
allow bootp;

ignore client-updates;
set vendorclass = option vendor-class-identifier;

option pxe-system-type code 93 = unsigned integer 16;

subnet 10.69.0.0 netmask 255.255.0.0 {
     option routers             10.69.0.1;
     option domain-name-servers 10.69.0.1;
     option subnet-mask         255.255.0.0;
     range dynamic-bootp        10.69.0.10 10.69.0.250;
     default-lease-time         21600;
     max-lease-time             43200;
     next-server                \$next_server;
     class "pxeclients" {
          match if substring (option vendor-class-identifier, 0, 9) = "PXEClient";
          if option pxe-system-type = 00:02 {
                  filename "ia64/elilo.efi";
          } else if option pxe-system-type = 00:06 {
                  filename "grub/grub-x86.efi";
          } else if option pxe-system-type = 00:07 {
                  filename "grub/grub-x86_64.efi";
          } else {
                  filename "pxelinux.0";
          }
     }

}
EOF
sed -i 's|listen-on port 53 { 127.0.0.1; };|listen-on port 53 { 10.69.0.1; };|g' /etc/cobbler/named.template
sed -i 's|allow-query     { localhost; };|allow-query     { 10.69/16; };|g' /etc/cobbler/named.template
echo 'DHCPDARGS="eth2";' > /etc/sysconfig/dhcpd
sed -i 's|subnet 192.168.1.0 netmask 255.255.255.0 {|subnet 10.69.0.0 netmask 255.255.0.0 {|g' /etc/cobbler/dhcp.template
service cobblerd restart
service httpd restart
cobbler sync
cobbler repo add --mirror=http://mirror.utexas.edu/epel/6/x86_64 --name=epel6
cobbler repo add --mirror=http://ftp.utexas.edu/centos/6.5/os/x86_64 --name=centos65
cobbler reposync
cobbler get-loaders
service cobblerd restart
cobbler sync


wget http://ftp.utexas.edu/centos/6.5/os/x86_64/isolinux/initrd.img
wget http://ftp.utexas.edu/centos/6.5/os/x86_64/isolinux/vmlinuz
cobbler distro add --name=centos65 --kernel /root/vmlinuz --initrd=/root/initrd.img --arch=x86_64 --ksmeta="tree=http://@@http_server@@/cobbler/repo_mirror/centos65"
cobbler profile add --name=compute --distro=centos65


# needed for tftp
service xinetd start
# NEED TO FIX THIS
service iptables stop
service httpd restart

chkconfig xinetd on
chkconfig iptables off
chkconfig cobblerd on
chkconfig httpd on

yum -y install pykickstart

echo "nameserver 10.69.0.1" >> /etc/resolve.conf

cobbler system add --name=c1-101.vmcluster.local --profile=compute --mac=08:00:27:83:d2:b5 --dns-name=c1-101.vmcluster.local --ip-address=10.69.0.10 --interface=eth0 --hostname=c1-101 --static=true --netmask=255.255.0.0 --kickstart=/var/lib/cobbler/kickstarts/sample.ks
