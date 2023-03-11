#!/bin/bash

TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
BACKEND=`curl -H "X-aws-ec2-metadata-token: $TOKEN" -v "http://169.254.169.254/latest/meta-data/tags/instance/Backend"`

cat > /var/www/html/page$${BACKEND}.html <<EOF
<h1>Welcome to backend $${BACKEND}</h1>
EOF
