# ---------- Build Stage ----------
FROM node:20-alpine AS build

WORKDIR /app

COPY app/package*.json ./

RUN npm ci

COPY app/ .

ARG REACT_APP_TMDB_API_KEY
ENV REACT_APP_TMDB_API_KEY=$REACT_APP_TMDB_API_KEY

RUN npm run build


# ---------- Production Stage ----------
FROM nginx:alpine

COPY --from=build /app/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]