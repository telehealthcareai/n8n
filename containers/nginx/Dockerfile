
FROM nginx:latest

RUN apt-get -qq update --yes \
    && apt-get -qq install --yes --no-install-recommends \
    cron \
    certbot \
    sed \
    python3-certbot-nginx \
    && rm -rf /var/lib/apt/lists/*

RUN rm /etc/nginx/conf.d/default.conf \
    && mkdir /etc/nginx/sites-available \
    && mkdir /etc/nginx/sites-enabled

COPY containers/nginx/scripts/create_symlinks.sh /tmp/create_symlinks.sh
COPY containers/nginx/scripts/entrypoint.sh /entrypoint.sh

# Generate a self-signed SSL certificate
RUN openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" \
    -keyout /tmp/nginx-selfsigned.key \
    -out /tmp/nginx-selfsigned.crt

ARG BASE_PATH=containers/nginx/data
COPY ${BASE_PATH}/fastcgi_params ${BASE_PATH}/mime.types ${BASE_PATH}/nginx.conf \
     ${BASE_PATH}/options-ssl-nginx.conf ${BASE_PATH}/proxy.conf ${BASE_PATH}/scgi_params /etc/nginx/
COPY ${BASE_PATH}/sites-available /etc/nginx/sites-available

WORKDIR /etc/nginx

RUN chmod +x /tmp/create_symlinks.sh /entrypoint.sh && . /tmp/create_symlinks.sh

ENTRYPOINT [ "/entrypoint.sh" ]
