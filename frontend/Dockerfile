# Этап 1: Сборка статики (builder)
FROM node:18-alpine AS builder

WORKDIR /app

# Копируем манифесты npm и устанавливаем зависимости
COPY package*.json ./
RUN npm install

# Копируем исходный код фронтенда и запускаем сборку
COPY . .
RUN npm run build

# Этап 2: Раздача статики через легковесный веб-сервер
FROM nginx:alpine

# Копируем собранные файлы (Vue кладет их в папку dist) в стандартную директорию Nginx
COPY --from=builder /app/dist /usr/share/nginx/html

# Копируем наш кастомный конфиг Nginx для проксирования API
COPY default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# Запускаем Nginx в foreground-режиме
CMD ["nginx", "-g", "daemon off;"]
