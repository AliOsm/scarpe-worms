# Pin the multi-architecture index so both release jobs use the same base.
FROM ruby:4.0.7-slim@sha256:ba6a00593739f9cb66de80ad2e395a93a52a13635867ee32918ba0ec083b1ff6
RUN gem install --no-document logger -v 1.7.0 && gem install --no-document base64 -v 0.3.0 \
    && useradd --system --uid 10001 --create-home burrow \
    && mkdir -p /app /var/lib/burrow && chown burrow:burrow /var/lib/burrow
WORKDIR /app
COPY lib/ lib/
COPY bin/server bin/healthcheck bin/
COPY LICENSE /app/LICENSE
COPY packaging/server/NOTICES.md /app/NOTICES.md
COPY packaging/ruby/licenses/Ruby-* /usr/local/share/licenses/ruby/
USER burrow
ENV BURROW_SERVER_DATA=/var/lib/burrow
EXPOSE 4388
VOLUME ["/var/lib/burrow"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["ruby", "bin/healthcheck"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["ruby", "bin/server"]
