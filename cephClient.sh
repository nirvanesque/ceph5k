#!/bin/bash

# Get the client keyring for Ceph production for current user. Store in /tmp on frontend.
curl -k https://api.grid5000.fr/sid/storage/ceph/auths/$USER.keyring | cat - > /tmp/ceph.client.$USER.keyring
