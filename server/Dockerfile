# Serveur de jeu dédié Ouche City (agent 10 / agent 12).
# Construction depuis la racine du dépôt : docker build -f server/Dockerfile -t ouche-city-server .
# Lancement : docker run -p 24680:24680/udp -e OUCHE_MAX_PLAYERS=16 ouche-city-server
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.4.1-stable
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 \
 && curl -fsSL -o /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
 && unzip /tmp/godot.zip -d /opt/godot && mv /opt/godot/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && rm -rf /tmp/godot.zip /var/lib/apt/lists/* \
 && useradd --create-home ouche

WORKDIR /opt/ouche
COPY --chown=ouche:ouche game/ game/
USER ouche
RUN godot --headless --path game --import >/dev/null 2>&1 || true

ENV OUCHE_PORT=24680 \
    OUCHE_HOST=0.0.0.0 \
    OUCHE_MAX_PLAYERS=16
EXPOSE 24680/udp
ENTRYPOINT ["godot", "--headless", "--path", "/opt/ouche/game", "--", "--server"]
