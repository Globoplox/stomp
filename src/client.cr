# connect (host

# send (with_receipt or not) to
# receive (from)
require "http/web_socket"
require "./stomp"

# TODO: inherit for WS instead of composing ?
class Stomp::Client #< HTTP::WebSocket

  getter server_version: Strign? = nil
  property logger : 
  # closed, disconnected, conected ?
  @state = :disconnected
  
  
  @on_connected: (Frame -> Void)? = nil

  def on_connected(&handler: Frame -> Void)
    @on_connected = handler
  end

  def handle_frame(frame)
    case {state, frame.command}
    when {_, Commands::ERROR} then raise frame.body     
    when {:disconnected, Commands::CONNECTED}
      # setup heart-beat listener
      @server_version = frame.headers["version"]
      @state = :connected
      on_connected.try &.call frame
    else raise "Unexpected state: #{@state}"
    end
  end

  def init
    on_close do
      @state = :closed
    end
    on_message do |message|
      handle_frame Frame.decode message
    end
  end
  
  def connect(accept_version = "1.2", virtual_host = "/", use_connect_frame = true, username = nil, password = nil, ask_hearbeat = 0)
    # write connect frame to ws to ws
    frame = Frame.new use_connect_frame ? Commands::CONNECT : Commands::STOMP
    frame.headers["accept-version"] = accept_version
    frame.headers["host"] = accept_version
    frame.headers["login"] = username unless username.nil?
    frame.headers["passcode"] = password unless password.nil?
    # todo support sending heartbeat
    frame.headers["heart-beat"] = "0,#{ask_hearbeat}"
    send frame.encode
  end

end

cli = Stomp::Client.new #nil
cli.on_connected do |f|
  p f
end
cli.connect
