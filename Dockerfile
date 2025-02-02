FROM alpine:latest

RUN apk add --no-cache bash git openssh-client

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
