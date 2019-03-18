#!/bin/bash

#
# Daemon for Telegraph
# (c) 2019 Mihail Podivilov
#
# See copyright notice in LICENSE
#

# Waiting for a new Telegraph device
# being presented in system
while :
do
  # If new Telegraph device found, run telegraph.sh
  if lsblk -r | grep -q "sd.*[1-9]"; then
    # Wait for 500 ms
    # for slow USB devices
    sleep 0.5

    # Run Telegraph
    bash telegraph.sh
  fi

  # Waiting for Telegraph device
  # to disappear from system
  while :
  do
    if lsblk -r | grep -q "sd.*[1-9]"; then
      :
    else
      break
    fi

    # Wait for 500 ms
    # to decrease the CPU utilization
    sleep 0.1
  done

  # Wait for 500 ms
  # to decrease the CPU utilization
  sleep 0.5
done
