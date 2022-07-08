ARG ELIXIR_VERSION=1.13
FROM elixir:${ELIXIR_VERSION} as build

COPY config /build/config
COPY lib /build/lib
COPY test /build/test
COPY mix.exs /build/mix.exs
COPY mix.lock /build/mix.lock

WORKDIR /build
ENV MIX_ENV=prod
ENV BUILD_WITHOUT_QUIC=1
RUN mix local.hex --force
RUN mix local.rebar --force
RUN mix deps.get
RUN mix release

RUN mv /build/_build/prod/rel/elightscape /app


FROM elixir:${ELIXIR_VERSION}

COPY --from=build /app /app
RUN useradd elightscape
USER elightscape
ENTRYPOINT [ "/app/bin/elightscape" ]
CMD [ "start" ]
