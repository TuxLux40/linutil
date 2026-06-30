#!/bin/sh -e
exec "$(dirname "$0")/security-hardening.sh" firewall "$@"
