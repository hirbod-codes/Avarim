FROM nginx:alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY ./nginx.conf /etc/nginx/nginx.conf

COPY ./build/avarim /usr/share/nginx/html/avarim

COPY ./certs /etc/nginx/certs

RUN mkdir -p /var/www/html && touch /var/www/html/39148404.txt

EXPOSE 80 443

CMD ["nginx", "-g", "daemon off;"]