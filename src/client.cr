require "http/web_socket"
require "./stomp"
require "./frames"

class Stomp::Client < HTTP::WebSocket
  #Log = Stomp::Log.for "client"
  @state = :disconnected
  
  getter server_version : String? = nil
  getter client_in_heartbeat = 0
  getter client_out_heartbeat = 0
  getter in_heartbeat = 0
  getter out_heartbeat = 0
  property heartbeat_tolerance = 1.2
  @last_client_beat = Time.monotonic
  @last_server_beat = Time.monotonic
  
  @on_connected: (Frame ->)? = nil
  def on_connected(&@on_connected: Frame ->) end
  @on_error: (Frame ->)? = nil
  def on_error(&@on_error: Frame ->) end

  def heartbeat(in in_span, out out_span)
    if in_span || out_span
      puts "Starting heartbeat"
      puts "Client must beat every #{out_span.milliseconds}" if out_span
      puts "Server must beat every #{in_span.milliseconds}" if in_span
      loop do
        sleep (out_span ? out_span : in_span).milliseconds
        beat if out_span && Time.monotonic - @last_client_beat > out_span.milliseconds
        if in_span && Time.monotonic - @last_server_beat > (in_span * @heartbeat_tolerance).milliseconds
          puts "server missed heartbeat: #{Time.monotonic - @last_server_beat} since last activity"
          close 500
        end
        break if closed?
      end
    end
  end
  
  def handle_frame(frame)
    case {@state, frame.command}
    when {:disconnected, Commands::ERROR}
      @on_error.try &.call frame
      close 400, frame.body
    when {_, Commands::ERROR}
      @on_error.try &.call frame
    when {:disconnected, Commands::CONNECTED}
      @server_version = frame.headers["version"]
      server_out_heartbeat, server_in_heartbeat = frame.headers["heart-beat"].split(",").map &.to_i
      @out_heartbeat = Math.max(@client_out_heartbeat, server_in_heartbeat) unless @client_out_heartbeat == 0 || server_in_heartbeat == 0
      @in_heartbeat = Math.max(@client_in_heartbeat, server_out_heartbeat) unless @client_in_heartbeat == 0 || server_out_heartbeat == 0
      spawn heartbeat @in_heartbeat, @out_heartbeat
      @state = :connected
      @on_connected.try &.call frame
    else raise "Unexpected state/command: #{@state}, #{frame.command}"
    end
  end

  def beat
    @last_client_beat = Time.monotonic
    send Frame::BEAT
  end
  
  def send(frame : Frame)
    @last_client_beat = Time.monotonic
    send frame.encode
  end
  
  def init
    on_close do
      @state = :closed
    end
    on_message do |message|
      @last_server_beat = Time.monotonic
      handle_frame Frame.decode message unless Frame.is_beat message
    rescue error
      puts error
    end
  end
  
  def connect(
    accept_version = "1.2",
    virtual_host = nil,
    use_connect_frame = true,
    username = nil,
    password = nil,
    in_heartbeat @client_in_heartbeat = 10000,
    out_heartbeat @client_out_heartbeat = 5000
  )
    init
    frame = Frame.new use_connect_frame ? Commands::CONNECT : Commands::STOMP
    frame.headers["accept-version"] = accept_version
    frame.headers["host"] = virtual_host unless virtual_host.nil?
    frame.headers["login"] = username unless username.nil?
    frame.headers["passcode"] = password unless password.nil?
    frame.headers["heart-beat"] = "#{client_out_heartbeat},#{client_in_heartbeat}"
    send frame
    run
  end

end

cli = Stomp::Client.new("localhost", "/ws", 15674)
cli.on_error do |frame|
  puts "Oh no an error !"
end
cli.on_close do |msg|
  puts "I GOT CLOSED ?!! #{msg}"
end
cli.on_connected do
  puts "Oh I'm connected, yummy !"
end
cli.connect username: "cc", password: "toto"
