use "bureaucracy"
use "collections"
use "cli"
use "logger"
use "net"
use "signals"
use "time"


actor Main
  """A basic line-oriented chat server used as a learning example.
     It features:
     - graceful shutdown of the server (triggered by sending `SIGTERM` and `SIGINT`)
     - logging which can be controlled via `PONY_LOG_LEVEL` environment variable
     - requires clients to provide their names
     - clients can send:
       - `/quit` - terminate the client's connection to the server and announces
         that this client has left
       - `/time` - the server sends the current time to the server
       - everything else is sent to all connected clients
  """
  new create(env: Env) =>
    let envMap = EnvVars(env.vars where prefix = "PONY_", squash = true)
    let logLevel = match envMap.get_or_else("log_level", "").lower()
    | "fine" => Fine
    | "info" => Info
    | "warn" => Warn
    | "error" => Error
    else
      Warn
    end

    let custodian = Custodian
    let logger = StringLogger(logLevel, env.out)
    let room = ChatRoom
    SignalHandler(TermHandler(custodian, logger), Sig.term())
    SignalHandler(TermHandler(custodian, logger), Sig.int())

    try
      let server = TCPListener(
        env.root as AmbientAuth,
        recover ChatServer(logger, room) end,
        "localhost",
        "8989"
      )

      logger(Info) and logger.log("server started")
      custodian(room)
      custodian(server)
    else
      logger(Error) and logger.log("failed to start server")
    end


class TermHandler is SignalNotify
  let _custodian: Custodian
  let _logger: Logger[String]

  new iso create(custodian: Custodian, logger: Logger[String]) =>
    _custodian = custodian
    _logger = logger

  fun ref apply(count: U32): Bool =>
    _logger(Info) and _logger.log("going now, bye!")
    _custodian.dispose()
    // don't keep listening for signal
    false


primitive PrintTime
  fun apply(): String =>
    """Returns the current time in UTC. e.g. `2019-03-04 19:26:14`"""
    (let sec: I64, let nsec: I64) = Time.now()
    try
      PosixDate(sec, nsec).format("%F %T %Z")?
    else
      "failed to format time"
    end

primitive AddrStr
  fun apply(n: NetAddress val): String =>
    """Returns the current `host:port` if available, `:` otherwise."""
    (let host, let port) =
      try n.name()?
      else ("", "")
      end
    host + ":" + port

type Nick is String


class ChatServer is TCPListenNotify
  let _logger: Logger[String]
  let _room: ChatRoom

  new create(logger: Logger[String], room: ChatRoom) =>
    _logger = logger
    _room = room

  fun ref listening(listen: TCPListener ref): None val =>
    _logger(Info) and _logger.log("listening on " + AddrStr(listen.local_address()))
    None

  fun ref not_listening(listen: TCPListener ref): None val =>
    _logger(Error) and _logger.log("failed to listen on " + AddrStr(listen.local_address()))
    None

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    // create a new `ChatConnection` that handles all I/O from the connecting client
    recover ChatConnection(_logger, _room) end

  fun ref closed(listen: TCPListener ref): None val =>
    None


class ChatConnection is TCPConnectionNotify
  """
  ChatConnection handles all I/O from a client. It manages state for the connecting client.
  """
  let _logger: Logger[String]
  let _room: ChatRoom
  var _nick: (Nick | None)

  new create(logger: Logger[String], room: ChatRoom) =>
    _logger = logger
    _room = room
    _nick = None

  fun ref accepted(conn: TCPConnection ref) : None val =>
    _logger(Info) and _logger.log("new client conection accepted from " + AddrStr(conn.remote_address()))
    conn.write("welcome! Please enter your name: \n")
    None

  fun ref connect_failed(conn: TCPConnection ref): None val =>
    // Hmmm?  This seems like it gets called if we were a client and not a server
    None

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso, times: USize): Bool =>
    _logger(Info) and _logger.log("received data from " + AddrStr(conn.remote_address()))
    // state management for client...not great but it's a start and good enough for an example
    match _nick
      | None =>
        match String.from_iso_array(consume data).>strip()
          | let nick: String val if nick.size() > 0 =>
            _nick = nick
            _room.add(conn, nick)
        else
          conn.write("Please enter your name: \n")
        end
      | let nick: String =>
        let line: String val = String.from_iso_array(consume data).>strip()
        match line
          | "/quit" =>
            _room.remove(conn)
            return false
          | "/time" => conn.write(PrintTime() + "\n")
          | let msg: String if msg.size() > 0 =>
            _room.message(nick, msg)
        end
    end
    true

  fun ref closed(conn: TCPConnection ref): None val =>
    _logger(Info) and _logger.log("client closed connection")
    _room.remove(conn)
    None


actor ChatRoom
  let _conns: MapIs[TCPConnection, Nick] = _conns.create()

  be dispose() =>
    message("server", "shutting down...")
    _shutdown()

  be _shutdown() =>
    for conn in _conns.keys() do
      conn.mute()
      conn.dispose()
    end
    _conns.clear()

  be add(conn: TCPConnection, nick: Nick) =>
    _conns(conn) = nick

  be remove(conn: TCPConnection) =>
    try
      let nick = _conns(conn)?
      _conns.remove(conn)?
      conn.mute()
      conn.dispose()
      message("server", nick + " left")
    end

  be message(nick: Nick, msg: String) =>
    for (conn, nick') in _conns.pairs() do
      if nick != nick' then
        conn.write(nick + ": " + msg + "\n")
      end
    end
