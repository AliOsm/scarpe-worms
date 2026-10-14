# Pin the multi-architecture index so both release jobs use the same base.
FROM ruby:3.4.7-slim@sha256:93dd13e28987e373857fbda4a7f4ae99e9f7acb6fcc266035e551229974d1c89
RUN gem install --no-document logger -v 1.7.0 && gem install --no-document base64 -v 0.3.0 \
    && useradd --system --uid 10001 --create-home burrow \
    && mkdir -p /app /var/lib/burrow && chown burrow:burrow /var/lib/burrow
WORKDIR /app
COPY lib/ lib/
COPY bin/server bin/healthcheck bin/
COPY LICENSE /app/LICENSE
COPY packaging/server/NOTICES.md /app/NOTICES.md
COPY packaging/macos/licenses/Ruby-* /usr/local/share/licenses/ruby/
USER burrow
ENV BURROW_SERVER_DATA=/var/lib/burrow
EXPOSE 4388
VOLUME ["/var/lib/burrow"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["ruby", "bin/healthcheck"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["ruby", "bin/server"]
