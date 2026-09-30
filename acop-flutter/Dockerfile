FROM nginx:alpine
COPY build/web /usr/share/nginx/html
# SPA routes plus ACOP API proxy.
RUN printf '%s\n' \
    'server {' \
    '    listen 80;' \
    '    root /usr/share/nginx/html;' \
    '    index index.html;' \
    '    location ^~ /acop {' \
    '        rewrite ^/acop/?(.*)$ /$1 break;' \
    '        proxy_pass http://csac-acop:8082;' \
    '        proxy_set_header Host $host;' \
    '        proxy_set_header X-Real-IP $remote_addr;' \
    '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' \
    '        proxy_set_header X-Forwarded-Proto $scheme;' \
    '    }' \
    '    location ^~ /upload/ {' \
    '        alias /data/upload/;' \
    '        try_files $uri =404;' \
    '    }' \
    '    location / {' \
    '        try_files $uri $uri/ /index.html;' \
    '    }' \
    '}' > /etc/nginx/conf.d/default.conf
EXPOSE 80
