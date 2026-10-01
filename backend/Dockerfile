FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /freefall-api ./cmd/api

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /freefall-api /freefall-api
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/freefall-api"]
