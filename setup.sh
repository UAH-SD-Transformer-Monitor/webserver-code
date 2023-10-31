#!/bin/bash
# Run these commands as a privileged user



installNodeRed () {

adduser nodered

usermod -a -G sudo nodered

su nodered -C "bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) --node20 --nodered-user=nodered --confirm-install --skip-pi"
node-red admin init

}

installFail2Ban () {

    sudo apt update && sudo apt upgrade -y

    sudo apt install fail2ban -y

    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

    sudo service fail2ban restart

}

installNginx () {

    sudo apt install build-essential git

    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo mkdir -p /etc/apt/keyrings

    sudo apt -y install curl gnupg2 ca-certificates lsb-release ubuntu-keyring
    curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor \
        | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
    gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
    http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
        | sudo tee /etc/apt/sources.list.d/nginx.list
    echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
        | sudo tee /etc/apt/preferences.d/99nginx
    sudo apt update
    sudo apt -y install nginx

cat <<EOF > /etc/nginx/nginx.conf

    user  nginx;
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
    mkdir /etc/nginx/sites-{availiable,enabled};


}

installEQMX () {

curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | sudo bash
sudo apt-get install emqx
sudo systemctl start emqx

}

installAcme() {

mkdir -p /var/www/html/letsencrypt/;
chown -R nginx:nginx /var/www/html/letsencrypt/;
git clone https://github.com/acmesh-official/acme.sh.git
mkdir -p /etc/acme/{config,certs};
cd ./acme.sh
./acme.sh --install -m $ACME_EMAIL \
            --home /etc/acme \
            --config-home /etc/acme/config \
            --cert-home /etc/acme/certs
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

installAcme();
installNginx();
installFail2Ban();
installEQMX();

}