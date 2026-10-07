FROM alpine:latest
RUN apk add --no-cache openssl dos2unix
WORKDIR /app
COPY gen-certs.sh .
RUN dos2unix gen-certs.sh && chmod +x gen-certs.sh
ENTRYPOINT ["./gen-certs.sh"]