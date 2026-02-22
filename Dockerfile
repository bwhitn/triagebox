FROM debian:trixie-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /srv
COPY public/ /srv/public/
COPY scripts/serve-compressed.py /srv/serve-compressed.py

EXPOSE 8080
CMD ["python3", "/srv/serve-compressed.py", "8080", "/srv/public"]
