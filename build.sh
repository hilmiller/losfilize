#!/bin/bash



#Have a list of configuration here
#MASTERPUBIP = 123.41.15.3
#INTERNALNODENETWORK = 
# Also, the hosts too maybe?


#Disable selinux
#Add the EPEL repository

# Get repos in order

run () {
	echo -n $1
	$2 &> /root/losfilize.log
	if [ $? -eq 0 ]; then
        	tput setaf 2
		echo " [ OK ]"
		tput sgr0
	else
		tput setaf 1
		echo " [ FAIL ]"
		tput sgr0
fi


}

run "Installing EPEL" "rpm --quiet -i http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm &> /root/losfilize.log"

run "Upgrading packages" "yum -y upgrade"

run "Disable selinux running now" "echo 0 > /selinux/enforce"
run "Disable selinux configuration" 'sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux'


echo -n Disabling selinux
echo 0 >/selinux/enforce
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
if [ $? -eq 0 ]; then
	tput setaf 2
	echo " [ OK ]"
	tput sgr0
else
	tput setaf 1
	echo " [ FAIL ]"
	tput sgr0
fi

yum -y install vim tmux

# Cobbler
yum -y install cobbler httpd wget

sed -i 's/^server: 127.0.0.1/server: 10.69.0.1/g' /etc/cobbler/settings
sed -i 's/^client_use_localhost: 0/client_use_localhost: 1/g' /etc/cobbler/settings
sed -i 's/^manage_dns: 0/manage_dns: 1/g' /etc/cobbler/settings

sed -i 's|^manage_forward_zones: \[\]|manage_forward_zones: \[\x27vmcluster.local\x27\]|g' /etc/cobbler/settings
sed -i 's|^manage_reverse_zones: \[\]|manage_reverse_zones: \[\x2710.69\x27\]|g' /etc/cobbler/settings


# Restarting here for new configs, even if they weren't on
service cobblerd restart
service httpd restart
cobbler repo add --mirror=http://mirror.utexas.edu/epel/6/x86_64 --name=epel6
cobbler repo add --mirror=http://ftp.utexas.edu/centos/6.5/os/x86_64 --name=centos65

#TURN THIS BACK ON
cobbler reposync


# cobbler system add --name=c1-101 --profile=compute --mac=08:00:27:83:d2:b5
# Install bind

yum -y install bind

sed -i 's|listen-on port 53 { 127.0.0.1; };|listen-on port 53 { 10.69.0.1; };|g' /etc/cobbler/named.template
sed -i 's|allow-query     { localhost; };|allow-query     { 10.69/16; };|g' /etc/cobbler/named.template
# Install dhcp

yum -y install dhcp

# Listen on interface
echo 'DHCPDARGS="eth2";' > /etc/sysconfig/dhcpd
sed -i 's|subnet 192.168.1.0 netmask 255.255.255.0 {|subnet 10.69.0.0 netmask 255.255.0.0 {|g' /etc/cobbler/dhcp.template

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

sed -i 's|manage_dhcp: 0|manage_dhcp: 1|g' /etc/cobbler/settings

sed -i 's|^next_server: 127.0.0.1|next_server: 10.69.0.1|g' /etc/cobbler/settings

# Have to restart here, because otherwise cobbler sync won't see the changes we made.
service cobblerd restart
cobbler sync

# We dont need to import one, we have perfectly good repos.

wget http://ftp.utexas.edu/centos/6.5/os/x86_64/isolinux/initrd.img
wget http://ftp.utexas.edu/centos/6.5/os/x86_64/isolinux/vmlinuz

cobbler distro add --name=centos65 --kernel /root/vmlinuz --initrd=/root/initrd.img --arch=x86_64 --ksmeta="tree=http://@@http_server@@/cobbler/repo_mirror/centos65"
cobbler profile add --name=compute --distro=centos65


# needed for tftp
service xinetd start

# NEED TO FIX THIS
service iptables stop

service httpd restart

chkconfig iptables off
chkconfig cobblerd on
chkconfig httpd on
echo 0 >/selinux/enforce


#cobbler system add --name=c1-101 --profile=compute --mac=08:00:27:83:d2:b5
#cobbler system add --name=c1-101.vmcluster.local --profile=compute --mac=08:00:27:83:d2:b5 --dns-name=c1-101.vmcluster.local --ip-address=10.69.0.10 --static=1
