#!/bin/bash
# Variables
domain="test.mgt.com"
db_name="magento"
db_user="magento_user"
db_password="strong_password"
phpmyadmin_domain="pma.mgt.com"
user="test-ssh"
group="clp"

# Update and install prerequisites
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip software-properties-common lsb-release ca-certificates apt-transport-https

# Add PHP repository and install PHP 8.1
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update
sudo apt install -y php8.1 php8.1-fpm php8.1-cli php8.1-mysql php8.1-curl php8.1-intl php8.1-xsl php8.1-mbstring php8.1-zip php8.1-bcmath php8.1-soap php8.1-gd php8.1-opcache php8.1-common

# Install MySQL
sudo apt install -y mysql-server
sudo mysql -e "CREATE DATABASE $db_name;"
sudo mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_password';"
sudo mysql -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Install NGINX
sudo apt install -y nginx

# Add Elasticsearch repository and install Elasticsearch
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update && sudo apt install -y elasticsearch
sudo systemctl enable elasticsearch
sudo systemctl start elasticsearch

# Install Redis
sudo apt install -y redis-server
sudo systemctl enable redis
sudo systemctl start redis

# Install Composer
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Install Magento
sudo mkdir -p /var/www/html/magento
sudo chown -R $USER:$USER /var/www/html/magento
cd /var/www/html/magento
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition .
sudo chown -R $user:$group /var/www/html/magento
sudo chmod -R 775 /var/www/html/magento

# Configure Magento for Redis
cd /var/www/html/magento
php bin/magento setup:config:set --cache-backend=redis --cache-backend-redis-server=127.0.0.1 --cache-backend-redis-port=6379
php bin/magento setup:config:set --session-save=redis --session-save-redis-host=127.0.0.1 --session-save-redis-port=6379

# Configure NGINX
sudo tee /etc/nginx/sites-available/$domain > /dev/null <<EOL
server {
    listen 80;
    server_name $domain;
    set \$MAGE_ROOT /var/www/html/magento;
    include /var/www/html/magento/nginx.conf.sample;
}
EOL
sudo ln -s /etc/nginx/sites-available/$domain /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Create a self-signed SSL certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/$domain.key -out /etc/ssl/certs/$domain.crt -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$domain"

# Redirect HTTP to HTTPS
sudo sed -i 's/listen 80;/listen 80; return 301 https:\/\/$host$request_uri;/' /etc/nginx/sites-available/$domain
sudo nginx -t
sudo systemctl reload nginx

# Install PHPMyAdmin
sudo apt install -y phpmyadmin
sudo tee /etc/nginx/sites-available/$phpmyadmin_domain > /dev/null <<EOL
server {
    listen 80;
    server_name $phpmyadmin_domain;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOL
sudo ln -s /etc/nginx/sites-available/$phpmyadmin_domain /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Install and configure Varnish
sudo apt install -y varnish
sudo mv /etc/varnish/default.vcl /etc/varnish/default.vcl.bak
sudo cp /var/www/html/magento/varnish/default.vcl /etc/varnish/default.vcl
sudo systemctl restart varnish

# Final permissions
sudo chown -R $user:$group /var/www/html/magento
sudo chmod -R 775 /var/www/html/magento

echo "Installation complete. Access Magento at http://$domain and PHPMyAdmin at http://$phpmyadmin_domain."
