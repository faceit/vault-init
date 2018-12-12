FROM gcr.io/docker-images-214113/alpine-base:3.8

ADD vault-init /usr/local/bin/vault-init

CMD ["/usr/local/bin/vault-init"]
