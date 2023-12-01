#!/bin/bash
# Run these commands as a privileged user



installNodeRed() {

adduser nodered

usermod -a -G sudo nodered

su nodered -C "bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --node20 --nodered-user=nodered --confirm-install --skip-pi"
node-red admin init

cat <<EOF > /etc/nginx/sites-availiable/node-red.conf;
upstream nodered {
  server 127.0.0.1:1880
}

server {
  server_name $NODERED_DOMAIN;
    listen 80;

    include includes/letsencrypt-webroot;
    location = /robots.txt {
    		add_header  Content-Type  text/plain;
    		return 200 "User-agent: *\nDisallow: /\n";
    	}
    
    return 301 https://$NODERED_DOMAIN\$request_uri;

}

server {
        listen 443 ssl;
        listen [::]:443 ssl;
        server_name $NODERED_DOMAIN;
        include includes/certs.conf;
        location / {
            proxy_pass http://nodered;
            
            #Defines the HTTP protocol version for proxying
                #by default it it set to 1.0.
                #For Websockets and keepalive connections you need to use the version 1.1
                proxy_http_version  1.1;

                #Sets conditions under which the response will not be taken from a cache.
                proxy_cache_bypass  \$http_upgrade;

                #These header fields are required if your application is using Websockets
                proxy_set_header Upgrade \$http_upgrade;

                #These header fields are required if your application is using Websockets
                proxy_set_header Connection "upgrade";

                #The \$host variable in the following order of precedence contains:
                #hostname from the request line, or hostname from the Host request header field
                #or the server name matching a request.
                proxy_set_header Host \$host;

                #Forwards the real visitor remote IP address to the proxied server
                proxy_set_header X-Real-IP \$remote_addr;

                #A list containing the IP addresses of every server the client has been proxied through
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

                #When used inside an HTTPS server block, each HTTP response from the proxied server is rewritten to HTTPS.
                proxy_set_header X-Forwarded-Proto \$scheme;

                #Defines the original host requested by the client.
                proxy_set_header X-Forwarded-Host \$host;

                #Defines the original port requested by the client.
                proxy_set_header X-Forwarded-Port \$server_port;

        }
}
EOF
}

installFail2Ban() {

    sudo apt update && sudo apt upgrade -y

    sudo apt install fail2ban -y

    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    sudo service fail2ban restart

}

installNginx() {

    sudo apt install build-essential git

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings

    sudo apt -y install curl gnupg2 ca-certificates lsb-release ubuntu-keyring
    # curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
    #     | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    # gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
    # echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    # http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
    #     | sudo tee /etc/apt/sources.list.d/nginx.list
    # echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
    #     | sudo tee /etc/apt/preferences.d/99nginx
    sudo apt update
    sudo apt -y install nginx

cat <<EOF > /etc/nginx/nginx.conf

    user  www-data;
    worker_processes  auto;

    error_log  /var/log/nginx/error.log notice;
    pid        /var/run/nginx.pid;


    events {
        worker_connections  1024;
    }

    stream {
        include /etc/nginx/streams/*;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                        '\$status \$body_bytes_sent "\$http_referer" '
                        '"\$http_user_agent" "\$http_x_forwarded_for"';

        access_log  /var/log/nginx/access.log  main;

        sendfile        on;
        #tcp_nopush     on;

        keepalive_timeout  65;

        #gzip  on;

        include /etc/nginx/sites-enabled/*;
        include /etc/nginx/conf.d/*.conf;
    }
EOF

    mkdir /etc/nginx/streams;
    mkdir /etc/nginx/includes;
    mkdir /etc/nginx/sites-{availiable,enabled};

cat <<EOF > /etc/nginx/includes/certs.conf;
ssl_certificate /etc/acme/live/$DOMAIN/fullchain.pem;
ssl_certificate_key /etc/acme/live/$DOMAIN/privkey.pem;
EOF
}

installEMQX() {

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get -y install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg


# Add the repository to Apt sources:
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin


docker network create --subnet=10.5.0.0/16 transformerMon

mkdir -p /docker/emqx

cat << EOF > /docker/emqx/docker-compose.yml
version: '3'

services:
  emqx1:
    image: emqx:5.3.0
    container_name: emqx1
    environment:
    - "EMQX_NODE_NAME=emqx@node1.emqx.io"
    - "EMQX_CLUSTER__DISCOVERY_STRATEGY=static"
    - "EMQX_CLUSTER__STATIC__SEEDS=[emqx@node1.emqx.io]"
    healthcheck:
      test: ["CMD", "/opt/emqx/bin/emqx", "ctl", "status"]
      interval: 5s
      timeout: 25s
      retries: 5
    networks:
      emqx-bridge:
        aliases:
        - node1.emqx.io
    ports:
      - 1883:1883
      - 8083:8083
      - 8084:8084
      - 8883:8883
      - 18083:18083 
    volumes:
      # - /opt/emqx/data:/opt/emqx/data
      # - /etc/acme/live/:/etc/emqx/etc
      # - /etc/emqx:/etc/emqx

networks:
  emqx-bridge:
    driver: bridge
EOF


cat <<EOF > /etc/nginx/sites-availiable/emqx.conf
#proxy for emqx @ port :18083
server {
        listen 80;
        listen [::]:80;
        include includes/letsencrypt-webroot;
        server_name $EMQX_DOMAIN;

        location = /robots.txt {
                add_header  Content-Type  text/plain;
                return 200 "User-agent: *\nDisallow: /\n";
        }
        return 301 https://$EMQX_DOMAIN\$request_uri;
}

server {
        listen 443 ssl;
        listen [::]:443 ssl;
        server_name $EMQX_DOMAIN;
        include includes/certs.conf;
        location / {
                proxy_pass http://127.0.0.1:18083;

                #Defines the HTTP protocol version for proxying
                #by default it it set to 1.0.
                #For Websockets and keepalive connections you need to use the version 1.1
                proxy_http_version  1.1;

                #Sets conditions under which the response will not be taken from a cache.
                proxy_cache_bypass  \$http_upgrade;

                #These header fields are required if your application is using Websockets
                proxy_set_header Upgrade \$http_upgrade;

                #These header fields are required if your application is using Websockets
                proxy_set_header Connection "upgrade";

                #The \$host variable in the following order of precedence contains:
                #hostname from the request line, or hostname from the Host request header field
                #or the server name matching a request.
                proxy_set_header Host \$host;

                #Forwards the real visitor remote IP address to the proxied server
                proxy_set_header X-Real-IP \$remote_addr;

                #A list containing the IP addresses of every server the client has been proxied through
                proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

                #When used inside an HTTPS server block, each HTTP response from the proxied server is rewritten to HTTPS.
                proxy_set_header X-Forwarded-Proto \$scheme;

                #Defines the original host requested by the client.
                proxy_set_header X-Forwarded-Host \$host;

                #Defines the original port requested by the client.
                proxy_set_header X-Forwarded-Port \$server_port;

        }
}
EOF

ln -s /etc/nginx/sites-availiable/emqx.conf /etc/nginx/sites-enabled/emqx.conf;
systemctl reload nginx
}

installAcme() {

mkdir -p /var/www/letsencrypt/;
chown -R www-data:www-data /var/www/letsencrypt/;

cat <<EOF > /etc/nginx/includes/letsencrypt-webroot

location /.well-known/acme-challenge/ {
    alias /var/www/letsencrypt/.well-known/acme-challenge/;
}
EOF

cat <<EOF > /etc/nginx/sites-enabled/default

server {
    listen 80;

    server_name $DOMAIN;


    # Let's Encrypt webroot
    include includes/letsencrypt-webroot;
}
EOF
systemctl reload nginx.service

git clone https://github.com/acmesh-official/acme.sh.git
mkdir -p /etc/acme/{config,certs,live};
cd ./acme.sh
./acme.sh --install -m $ACME_EMAIL \
            --home /etc/acme \
            --config-home /etc/acme/config \
            --cert-home /etc/acme/certs


}

obtainCerts() {
/etc/acme/acme.sh --issue -d $DOMAIN -d $EMQX_DOMAIN -d $NODERED_DOMAIN -w /var/www/letsencrypt/;
/etc/acme/acme.sh --install-cert -d $DOMAIN -d $EMQX_DOMAIN -d $NODERED_DOMAIN \
 --key-file /etc/acme/live/$DOMAIN/privkey.pem \
 --fullchain-file /etc/acme/live/$DOMAIN/fullchain.pem \
 --reloadcmd 'systemctl reload nginx';
}

main() {

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

if [ -z ${ACME_EMAIL+x} ]; 
  then
    echo "Set ACME_EMAIL by exporting this variable with a valid email";
    exit 1;
  fi

if [ -z ${DOMAIN+x} ]; 
  then
    echo "Set DOMAIN by exporting this variable with a domain that points to this server";
    exit 1;
  fi
if [ -z ${EMQX_DOMAIN+x} ]; 
  then
    echo "Set EMQX_DOMAIN by exporting this variable with a domain that points to this server";
    exit 1;
  fi
if [ -z ${NODERED_DOMAIN+x} ]; 
  then
    echo "Set NODERED_DOMAIN by exporting this variable with a domain that points to this server";
    exit 1;
  fi

installNginx
installAcme
installFail2Ban
installEMQX
obtainCerts
rm /etc/nginx/sites-enabled/default;
systemctl reload nginx

}

main


