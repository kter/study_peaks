FROM golang:1.22-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o /api

FROM gcr.io/distroless/static-debian12
COPY --from=builder /api /api
EXPOSE 8080
CMD ["/api"]
