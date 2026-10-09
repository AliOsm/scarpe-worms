FROM ruby:3.4.7-slim
RUN gem install --no-document logger -v 1.7.0 && gem install --no-document base64 -v 0.3.0 \
    && useradd --system --uid 10001 --create-home burrow \
    && mkdir -p /app /var/lib/burrow && chown burrow:burrow /var/lib/burrow
WORKDIR /app
COPY lib/ lib/
COPY bin/server bin/healthcheck bin/
USER burrow
ENV BURROW_SERVER_DATA=/var/lib/burrow
EXPOSE 4388
VOLUME ["/var/lib/burrow"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["ruby", "bin/healthcheck"]
STOPSIGNAL SIGTERM
ENTRYPOINT ["ruby", "bin/server"]
