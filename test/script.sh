#!/bin/sh 

# Run buitin spec tests
bundle exec rake test

# Run litmus test
bundle exec dav4rack --root /tmp/dav-file-store

DAV_PID = $?

cd /tmp/litmus/litmus-0.13 
make URL=http://localhost:3000/ check

kill $DAV_PID
