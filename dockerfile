FROM alpine:3.20
RUN apk add --no-cache tar zstd jq
COPY install-into-vm.sh /usr/local/bin/install-into-vm.sh
RUN chmod +x /usr/local/bin/install-into-vm.sh