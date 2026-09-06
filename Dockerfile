FROM node:20-alpine AS build

WORKDIR /app

COPY app/package*.json ./

RUN npm ci

COPY app/ .

ARG REACT_APP_TMDB_API_KEY
ENV REACT_APP_TMDB_API_KEY=$REACT_APP_TMDB_API_KEY

RUN npm run build


FROM nginx:1-alpine-slim

RUN addgroup -S nginxgroup && \
    adduser -S nginxuser -G nginxgroup

COPY --from=build /app/build /usr/share/nginx/html

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN sed -i 's|^[[:space:]]*pid[[:space:]].*;|pid /tmp/nginx.pid;|' /etc/nginx/nginx.conf && \
    mkdir -p /var/cache/nginx /var/run/nginx && \
    chown -R nginxuser:nginxgroup \
        /var/cache/nginx \
        /var/run/nginx \
        /usr/share/nginx/html \
        /etc/nginx

USER nginxuser

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]