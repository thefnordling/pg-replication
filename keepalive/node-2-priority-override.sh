#!/bin/bash

if [[ -f /etc/keepalived/priority_override ]]; then
    exit 0
else
    exit 1
fi
