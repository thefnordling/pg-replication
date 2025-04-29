## Overview Keepalive.d ##

allocate an ip (192.168.1.243/24) for a floating vrrp address

create an a record for pg.home.arpa => 192.168.1.243

ensure the virtual router id (in the config files i used 51) is safe to use and will not cause a collision on the network

determine the proper network interface on both pg1 and pg2 by running `ip addr show` use that instead of eth0 (if different) in the respective keepalive configuration file.

## Installation ##

### ON BOTH NODES ##

we're going to run some healthchecks, so let's set up a user to do that:

`sudo useradd --system --no-create-home --shell /usr/sbin/nologin keepalived_script`

the keepalived bundled in the ubuntu repositories is all messed up, so we'll compile and install from source.

```
sudo apt update
sudo apt install -y autoconf automake libtool build-essential libssl-dev libpopt-dev libsystemd-dev pkg-config curl
cd /usr/local/src
sudo curl -LO https://github.com/acassen/keepalived/archive/refs/tags/v2.3.3.tar.gz
sudo tar -xzf v2.3.3.tar.gz
cd keepalived-2.3.3
sudo ./autogen.sh
sudo ./configure --enable-systemd
sudo make
sudo make install
sudo ln -sf /usr/local/sbin/keepalived /usr/sbin/keepalived
sudo systemctl daemon-reexec
```

copy the corresponding configuration file to `/etc/keepalived/keepalived.conf`.  Edit the virtual router id, ip address and network interface as appropriate.

enable & start the service:
```
sudo systemctl enable keepalived
sudo systemctl start keepalived
```

## test it out ##

on the primary node, run `ip addr show` and confirm the vrrp address is on the network adapter.

on the primary node (pg1) stop postgres

`sudo systemctl stop postgresql`

wait a few seconds and run `ip addr show` on the primary node, confirm the vrrp address is not there.

check the secondary node - it should be there

now start postgres on node1

`sudo systemctl start postgresql` 

wait a few seconds, and check and confirm the ip address has gone back to the primary.