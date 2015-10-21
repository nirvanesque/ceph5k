#!/bin/bash

curl -k https://api.grid5000.fr/sid/storage/ceph/auths/$USER.keyring | cat - > /tmp/ceph.client.$USER.keyring
