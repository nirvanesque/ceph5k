#!/bin/bash

# Get the client keyring for Ceph production for current user. Store in /tmp on frontend.
if [ $1 == "" ] ; then
   echo "$0: managed Ceph site expected - rennes or nantes"
   exit 3
fi
mkdir -p /tmp/$1
curl -k https://api.grid5000.fr/sid/sites/$1/storage/ceph/auths/$USER.keyring | cat - > /tmp/$1/ceph.client.$USER.keyring
