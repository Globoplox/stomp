require "http/web_socket"
require "./stomp"
require "./frames"

# TODO: inherit for WS instead of composing ?
class Stomp::Client < HTTP::WebSocket
  #Log = Stomp::Log.for "client"

  getter server_version : String? = nil

  # closed, disconnected, conected ?
  @state = :disconnected
  
  @on_connected: (Frame ->)? = nil
  def on_connected(&@on_connected: Frame ->) end

  @on_error: (Frame ->)? = nil
  def on_error(&@on_error: Frame ->) end

  def handle_frame(frame)
    case {@state, frame.command}
    when {:disconnected, Commands::ERROR}
      @on_error.try &.call frame
      close 400, frame.body
    when {:disconnected, Commands::CONNECTED}
      # setup heart-beat listener
      @server_version = frame.headers["version"]?
      #Log.error "Connected frame from server is missing the version header" if @server_version.nil?
      @state = :connected
      @on_connected.try &.call frame
    else raise "Unexpected state/command: #{@state}, #{frame.command}"
    end
  end

  def init
    on_close do
      @state = :closed
    end
    on_message do |message|
      #Log.debug message
      handle_frame Frame.decode message
    end
    self
  end
  
  def connect(accept_version = "1.2", virtual_host = "/", use_connect_frame = true, username = nil, password = nil, ask_hearbeat = 0)
    init
    # write connect frame to ws to ws
    frame = Frame.new use_connect_frame ? Commands::CONNECT : Commands::STOMP
    frame.headers["accept-version"] = accept_version
    frame.headers["host"] = virtual_host
    frame.headers["login"] = username unless username.nil?
    frame.headers["passcode"] = password unless password.nil?
    # todo support sending heartbeat
    frame.headers["heart-beat"] = "0,#{ask_hearbeat}"
    send frame.encode
    run
  end

end

cli = Stomp::Client.new("localhost", "/ws", 15674)
cli.on_error do |frame|
  puts "Oh no an error ! #{frame.body}"
end
cli.on_connected do
  puts "Oh I'm connected, yummy !"
end
cli.connect username: "cc", password: "toto"
