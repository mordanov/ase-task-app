# Stage: borrow curl from ubi9-minimal (pre-installed as curl-minimal; ubi9-micro has none)
FROM registry.access.redhat.com/ubi9-minimal AS curl-provider

FROM quay.io/keycloak/keycloak:24.0.3 AS builder

# Pre-build Keycloak with postgres driver and optimized startup
ENV KC_DB=postgres
ENV KC_HTTP_ENABLED=true
ENV KC_HOSTNAME_STRICT=false
ENV KC_PROXY_HEADERS=xforwarded
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build --db=postgres

# ─── Runtime image ───────────────────────────────────────────────────────────
FROM quay.io/keycloak/keycloak:24.0.3

COPY --from=builder /opt/keycloak/ /opt/keycloak/

# Copy curl binary + shared libraries from the ubi9-minimal stage
COPY --from=curl-provider /usr/bin/curl /usr/bin/curl
COPY --from=curl-provider /usr/lib64/ /usr/lib64/

# Realm template — placeholders replaced at container startup via docker-entrypoint.sh
COPY realm-export.json /opt/keycloak/data/import/realm-export.json.tmpl

COPY docker-entrypoint.sh /docker-entrypoint.sh
USER root
RUN chmod +x /docker-entrypoint.sh && \
    chown -R 1000:1000 /opt/keycloak/data/import
USER 1000

EXPOSE 8080 9000

ENTRYPOINT ["/docker-entrypoint.sh"]

# --optimized skips the build step since we pre-built in the builder stage
CMD ["start", "--optimized", "--import-realm"]
