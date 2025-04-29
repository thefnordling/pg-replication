#!/bin/bash
logger -t keepalived "Promoting PostgreSQL to primary and bumping priority"

# Promote PostgreSQL
pg_ctlcluster 16 main promote

# Bump Keepalived priority permanently for this node
echo 150 > /etc/keepalived/priority_override
systemctl restart keepalived
