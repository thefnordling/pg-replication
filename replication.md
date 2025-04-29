# PG Replication Setup #

pg1 is the primary server (192.168.1.241)
pg2 is the replica server (192.168.1.242)

we'll set up pg1/pg2 manually as we'll just be doing that 1x

we'll use ansible to manage network permissions, to deploy pg_hba.conf changes to all the nodes

## ON EACH NODE ##

update apt and install postgres

apt-get update && apt-get install postgresql -y

## ON NODE 1 ##

connect to postgres, and create the superuser and replication user:

`sudo -u postgres psql`

```
CREATE ROLE gary WITH LOGIN PASSWORD 'potato' SUPERUSER CREATEDB CREATEROLE;
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'tyrellcorporation';
```

configure postgres to listen to all addresses and to enable replicatgion:

`sudo vi /etc/postgresql/16/main/postgresql.conf`

edit the file to have these values:

```
set listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
#presuming 50G of data/day, set it to retain a generous half day of lag
wal_keep_size = 25GB
hot_standby = on
```

then run

`sudo systemctl restart postgresql`

confirm we're listening on 0.0.0.0:5432

`netstat -an | grep 5432`

## ON NODE 2 ##

edit the config file 

`sudo vi /etc/postgresql/16/main/postgresql.conf`

and apply these settings:

```
listen_address = '*'
hot_standby = on
```

then run

`sudo systemctl restart postgresql`

confirm we're listening on 0.0.0.0:5432

`netstat -an | grep 5432`

## ON BOTH NODES ##

Postgres replicates users and roles.  Postgres does not replicate configuration files.  Network access to postgres is gated by a configuration file @ /etc/postgresql/16/main/pg_hba.conf.  This means that we have to update our network access in multiple places when we make changes.  This sucks, so we won't do that.  We will use ansible.

## FROM YOUR LINUX WORKSTATION ##

ensure you have a sudo-capable ssh key that works for pg1 and pg2.
the user you are connecting to pg1 and pg2 as should have a user in the sudoers file with ALL=(ALL) NOPASSWD:ALL

### install ansible ###

```
sudo apt install -y software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible python3-pip python3-venv
```

pull in the ansible scripts
```
cd ~
git clone https://github.com/thefnordling/pg-replication.git
cd pg-replication
```
### edit variables for hba provisioning ###

edit vars.users and vars.trusted_networks to reflect the users and networks you want to be able to access postgres, and then run the playbook:

```
python3 -m venv .venv
source .venv/bin/activate
ansible-playbook ./playbooks/update-hba.yml
```

reload postgres (no need to restart for the hba changes to get picked up) to pick up the new changes

test it works (from pg2):

`psql -h pg1 -U gary -d postgres`

## ON NODE 2 ##

stop postgres

`sudo systemctl stop postgresql`

delete any existing data/databases:

`sudo sudo find /var/lib/postgresql/16/main/ -mindepth 1 -delete`

backup the production db to node 2:

`sudo PGPASSWORD='tyrellcorporation' pg_basebackup -h 192.168.1.241 -D /var/lib/postgresql/16/main -U replicator -P --wal-method=stream`

Create standby.signal to mark as replica:

`sudo touch /var/lib/postgresql/16/main/standby.signal`

configure the replica append to this file:

`sudo vi /var/lib/postgresql/16/main/postgresql.auto.conf`

```
primary_conninfo = 'host=192.168.1.241 port=5432 user=replicator password=tyrellcorporation'
```

make it all owned by postgres user: 

`sudo chown -R postgres:postgres /var/lib/postgresql/16/main`

restart pg on node 2:

`sudo systemctl start postgresql`

confirm pg starts up on node 2.  if any issues check logs: `sudo cat /var/log/postgresql/postgresql-16-main.log` and/or `sudo journalctl -u postgresql -n 50 --no-pager`

## ON NODE 1 ##

then from node 1, confirm replication is working:

psql -h pg1 -U gary -d postgres

SELECT client_addr, state, sync_state FROM pg_stat_replication;

you should see something like this:

  client_addr  |   state   | sync_state
---------------+-----------+------------
 192.168.1.242 | streaming | async

### test/validate replication, still on node 1 ###

CREATE DATABASE myappdb;

-- Connect into the new database
\c myappdb

-- 2. Create a sample table
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL
);

-- 3. Insert some sample rows
INSERT INTO employees (name, department) VALUES
('Alice', 'Engineering'),
('Bob', 'Finance'),
('Charlie', 'Sales');

### create a new user with owner-access to the database ###

-- 4. Create a user who will own the database
CREATE ROLE appuser WITH LOGIN PASSWORD 'boat';

-- 5. Grant ownership of the database to the user
-- (First disconnect, because you can't reassign ownership while connected)
\c postgres

ALTER DATABASE myappdb OWNER TO appuser;
\c myappdb

GRANT CONNECT ON DATABASE myappdb TO appuser;
GRANT USAGE ON SCHEMA public TO appuser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO appuser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO appuser;

### update hba ###

update the users in the ansible playbook:
```
      - name: appuser
        cidr: 0.0.0.0/0
```

## Verify replication from Node 1 ##

`psql -h pg2 -U appuser -d myappdb` then  `select * from employees;`

this should produce
```
 id |  name   | department
----+---------+-------------
  1 | Alice   | Engineering
  2 | Bob     | Finance
  3 | Charlie | Sales
(3 rows)
```