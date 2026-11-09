FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY internal ./internal
COPY rpc ./rpc
COPY acop ./acop
COPY ServerBot ./ServerBot
COPY emapps ./emapps
RUN CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o /out/rpc ./rpc && \
    CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o /out/acop ./acop && \
    CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o /out/serverbot ./ServerBot && \
    CGO_ENABLED=0 go build -buildvcs=false -trimpath -ldflags='-s -w' -o /out/emapps ./emapps

FROM alpine:3.23
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 10001 csac && adduser -D -H -u 10001 -G csac csac && \
    mkdir -p /data /app/lib && chown csac:csac /data /app/lib
COPY --from=build /out/ /app/
COPY LICENSE NOTICE /usr/share/licenses/csac/
LABEL org.opencontainers.image.source="https://github.com/chemsource/CsAC"
ENV TZ=Asia/Shanghai
WORKDIR /data
USER csac:csac
CMD ["/app/rpc"]
