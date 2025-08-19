#!/bin/bash

set -ex

# Check if sugar is avaiable
if ! [ -x "$(command -v sugar)" ]; then
    echo "Error: sugar is not installed." >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
echo ${script_dir}

# project directory (root of the literev project)
project_dir="$script_dir/.envs"
echo "${project_dir}"

# Check .env exists for environment variabes
if [ -f "$project_dir/.env" ]; then
    # Load Environment Variables
    echo "Loading .env file..."
    source "$project_dir/.env"
else
    echo "Error: .env file not found." >&2
    exit 1
fi

## Check if ENV is set to prod or staging
if [[ "$ENV" != "prod" ]] && [[ "$ENV" != "staging" ]]; then
    echo "Error: ENV should be set to prod or staging." >&2
    echo "This script should be run in a production or staging environment." >&2
    exit 1
fi

# Check if CERTBOT_DOMAIN is set and not empty
if [ -z "$CERTBOT_DOMAIN" ]; then
    echo "Error: CERTBOT_DOMAIN is not set or empty." >&2
    exit 1
fi

# Check if CERTBOT_EMAIL is set and not empty
if [ -z "$CERTBOT_EMAIL" ]; then
    echo "Error: CERTBOT_EMAIL is not set or empty." >&2
    exit 1
fi

#
DOMAINS=($CERTBOT_DOMAIN)
RSA_KEY_SIZE=4096
EMAIL=${CERTBOT_EMAIL}

echo "----> Creating dummy certificate for $DOMAINS ..."
path="/etc/letsencrypt/live/$DOMAINS"

sudo mkdir -p /var/log/letsencrypt

sugar compose run --service certbot \
    --options "--rm --remove-orphans --entrypoint mkdir" --cmd "-p $path"

sugar compose run --service certbot \
    --options "--rm --remove-orphans --entrypoint openssl" \
    --cmd "req -x509 -nodes -newkey rsa:$RSA_KEY_SIZE -days 1 \
        -keyout $path/privkey.pem \
        -out $path/fullchain.pem \
        -subj /CN=localhost"

echo "----> Starting nginx ..."
sugar compose up --services nginx --options "--force-recreate -d"

echo "----> Deleting dummy certificate for $DOMAINS ..."
sugar compose run --service certbot \
    --options "--rm --remove-orphans --entrypoint rm" \
    --cmd "-Rf /etc/letsencrypt/live/$DOMAINS \
        -Rf /etc/letsencrypt/archive/$DOMAINS \
        -Rf /etc/letsencrypt/renewal/$DOMAINS.conf"

echo "----> Requesting Let's Encrypt certificate for $DOMAINS ..."
domain_args=""
for domain in "${DOMAINS[@]}"; do
    domain_args="$domain_args -d $domain"
done

# Select appropriate email arg
case "$EMAIL" in
    "") email_arg="--register-unsafely-without-email" ;;
    *) email_arg="--email $EMAIL" ;;
esac

# Enable staging mode if needed
staging_arg=""
if [ "${STAGING_MODE:-0}" != "0" ]; then
    staging_arg="--dry-run"
fi

sugar compose run --service certbot \
    --options "--rm --remove-orphans --entrypoint certbot" \
    --cmd "certonly --webroot -w /var/www/certbot \
        $staging_arg \
        $email_arg \
        $domain_args \
        --rsa-key-size $RSA_KEY_SIZE \
        --agree-tos \
        --no-eff-email \
        --force-renewal"

echo "----> Reloading nginx ..."
sugar compose exec --service nginx --cmd "nginx -s reload"

nginx_conf=$(sugar compose exec --service nginx --cmd \
  "sh -lc 'grep -l \"server_name[[:space:]]\\+${CERTBOT_DOMAIN};\" /etc/nginx/conf.d/*.conf /etc/nginx/conf.d/*.nginx.conf 2>/dev/null | head -n1'" \
)
if [ -z "$nginx_conf" ]; then
  echo "Could not find nginx server block for ${CERTBOT_DOMAIN} in /etc/nginx/conf.d"
  exit 1
fi
echo "Using nginx conf: $nginx_conf"

if sugar compose exec --service nginx --cmd "test -f $nginx_conf"; then
    echo "Nginx configuration file found. Updating..."

    sugar compose exec --service nginx --cmd \
        "sed -i 's/listen[[:space:]]*443;/listen 443 ssl;/' $nginx_conf"

    echo "----> Enabling SSL certificates in Nginx configuration..."

    sugar compose exec --service nginx --cmd \
        "sed -i 's|# ssl_certificate /etc/letsencrypt/live/$CERTBOT_DOMAIN/fullchain.pem;|ssl_certificate /etc/letsencrypt/live/$CERTBOT_DOMAIN/fullchain.pem;|' $nginx_conf"

    sugar compose exec --service nginx --cmd \
        "sed -i 's|# ssl_certificate_key /etc/letsencrypt/live/$CERTBOT_DOMAIN/privkey.pem;|ssl_certificate_key /etc/letsencrypt/live/$CERTBOT_DOMAIN/privkey.pem;|' $nginx_conf"

    echo "SSL certificate paths have been uncommented in Nginx configuration."

else
    echo "Nginx configuration file not found inside the container!"
    exit 1
fi

echo "----> Reloading Nginx with SSL ..."
sugar compose exec --service nginx --cmd "nginx -s reload"

echo "SSL setup complete!"
