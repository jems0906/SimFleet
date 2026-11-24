FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG VITE_API_URL=http://localhost:8000
ENV VITE_API_URL=$VITE_API_URL
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
RUN mkdir -p /var/cache/nginx /etc/nginx/conf.d /var/run \
	&& chown -R 101:101 /usr/share/nginx/html /var/cache/nginx /etc/nginx/conf.d /var/run
USER 101
