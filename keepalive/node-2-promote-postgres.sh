#!/bin/bash
logger -t keepalived "Promoting PostgreSQL to primary and raising priority"

# Promote PostgreSQL to read/write
pg_ctlcluster 16 main promote

# Create the priority override file so this node gets +50 priority weight
echo 1 > /etc/keepalived/priority_override

# Reload keepalived to re-evaluate scripts and recalculate effective priority
systemctl restart keepalived