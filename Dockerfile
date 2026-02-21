FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY public/ /srv/public/

EXPOSE 8080
CMD ["python3", "-m", "http.server", "8080", "--directory", "/srv/public"]
