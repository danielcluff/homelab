FROM nginxinc/nginx-unprivileged:1.29.5-alpine

COPY default.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html
COPY hosting/ /usr/share/nginx/html/hosting/

USER 101
