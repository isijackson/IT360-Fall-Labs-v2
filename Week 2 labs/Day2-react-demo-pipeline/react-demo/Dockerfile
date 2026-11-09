# Stage 1: build the React app with Node
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY public ./public
COPY src ./src
ENV CI=true
RUN npm test -- --watchAll=false && npm run build

# Stage 2: serve the static build with nginx
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build /usr/share/nginx/html
EXPOSE 80
