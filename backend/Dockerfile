# Этап 1: Сборка (builder)
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Копируем файлы зависимостей и скачиваем их
COPY go.mod go.sum ./
RUN go mod download

# Копируем весь остальной исходный код
COPY . .

# Собираем статически слинкованный бинарный файл (выключаем CGO для работы в Alpine)
RUN CGO_ENABLED=0 GOOS=linux go build -o momo-backend ./cmd/api

# Этап 2: Финальный легковесный образ
FROM alpine:3.19

WORKDIR /app

# Копируем только готовый бинарник из первого этапа
COPY --from=builder /app/momo-backend .

# Бэкенд Momo Store обычно слушает порт 8081
EXPOSE 8081

# Запускаем приложение
ENTRYPOINT ["./momo-backend"]
