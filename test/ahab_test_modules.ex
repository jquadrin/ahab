defmodule Ahab.TestModule do
  def start_link do
    pid = spawn_link(__MODULE__, :init, [])
    {:ok, pid}
  end

  def init do
    {:ok, socket} = Ahab.init_ack
    loop(socket)
  end

  def loop(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, "exit"} -> 
        exit("test called exit")
      {:ok, msg} ->
        :gen_tcp.send(socket, msg)
        loop(socket)
      {:error, reason} -> 
        exit(reason)
    end
  end
end

defmodule Ahab.TestBadModule do
  def start_link do
    raise "Error starting up"
    {:ok, 1}
  end
end
