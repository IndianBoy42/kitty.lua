#!/usr/bin/env sh
# Lil shell script to send SIGUSR1
if [ -z "$1" ]; then
	echo "Error: Please provide a process ID."
	exit 1
fi

if [ ! -d /proc/$1 ]; then
	echo "Error: Invalid process ID."
	exit 1
fi

kill -USR1 "$1"
