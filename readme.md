A basic line-oriented chat server used as a learning example.

It features:
- graceful shutdown of the server (triggered by sending `SIGTERM` and `SIGINT`)
- logging which can be controlled via `PONY_LOG_LEVEL` environment variable
- requires clients to provide their names
- clients can send:
    - `/quit` - terminate the client's connection to the server and announces
    that this client has left
    - `/time` - the server sends the current time to the server
    - everything else is sent to all connected clients

## Requirements

- [Pony compiler](https://github.com/ponylang/ponyc/blob/master/README.md#installation)

## Build

    ponyc

## Run

    ./main

To run with various log levels:

    PONY_LOG_LEVEL=<log-level> ./main

Where `<log-level>` is one of `fine`, `info`, `warn`, `error`
