FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
RUN sed -i 's@^pid .*;@pid /tmp/nginx.pid;@' /etc/nginx/nginx.conf \
	&& mkdir -p /var/cache/nginx /etc/nginx/conf.d \
	&& chown -R 101:101 /usr/share/nginx/html /var/cache/nginx /etc/nginx/conf.d
USER 101
