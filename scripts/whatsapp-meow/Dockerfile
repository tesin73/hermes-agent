FROM golang:1.21-alpine AS builder

RUN apk add --no-cache git gcc musl-dev sqlite-dev

WORKDIR /app
COPY go.mod .
RUN go mod download

COPY main.go .
RUN go build -o whatsapp-meow main.go

FROM alpine:latest

RUN apk add --no-cache ca-certificates sqlite-libs

WORKDIR /app
COPY --from=builder /app/whatsapp-meow .

ENV WHATSMEOW_SESSION=default
ENV WHATSMEOW_PORT=3002

EXPOSE 3002

CMD ["./whatsapp-meow"]
