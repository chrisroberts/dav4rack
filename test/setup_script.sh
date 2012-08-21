#!/bin/sh

rm -rf /tmp/litmus
mkdir /tmp/litmus
wget -O /tmp/litmus/litmus-0.13.tar.gz http://www.webdav.org/neon/litmus/litmus-0.13.tar.gz
tar -C /tmp/litmus -xvzf /tmp/litmus/litmus-0.13.tar.gz
cd /tmp/litmus/litmus-0.13
./configure
