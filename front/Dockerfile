# --- build ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

# --- runtime ---
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
COPY docker-entrypoint.sh /docker-entrypoint.d/40-config-js.sh
RUN sed -i 's/\r$//' /docker-entrypoint.d/40-config-js.sh && chmod +x /docker-entrypoint.d/40-config-js.sh
ENV API_URL=http://localhost:8000
EXPOSE 80
