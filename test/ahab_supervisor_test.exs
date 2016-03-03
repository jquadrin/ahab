defmodule Ahab.Supervisor.Test do
  use ExUnit.Case, async: false

  import Supervisor.Spec

  setup_all do
    {:ok, _} = Application.ensure_all_started(:logger) 
    Logger.remove_backend(:console, [flush: true])
    on_exit(fn() -> Logger.add_backend(:console, [flush: true]) end)
  end

  test "start_link/1" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    assert :proc_lib.translate_initial_call(pid) == {Ahab.Supervisor, :init, 2}
    :gen_tcp.close(lsock)
  end
  
  test 'async accept handles closed lsocket' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    Process.flag(:trap_exit, true)
    :gen_tcp.close(lsock)
    assert_receive {:'EXIT', ^pid, reason}
    assert reason == :closed
  end
   
  test 'accept two connections' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    sock1 = socket(9999)
    sock2 = socket(9999)
    socket_ack(sock1)
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 2}
    :gen_tcp.close(lsock)
  end
  
  test 'accept after a connection exits' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    sock1 = socket(9999)
    socket_ack(sock1)
    :gen_tcp.send(sock1, "exit")
    sock2 = socket(9999)
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.close(lsock)
  end
  
  test 'continue after child does not start' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestBadModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    _sock = socket(9999)
    assert %{active: 0, specs: 1, supervisors: 0, workers: 0} == Supervisor.count_children(pid)
    assert true == Process.alive?(pid)
    :gen_tcp.close(lsock)
  end
    
  test 'accepting pauses in accept call' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    _sock1 = socket(9999)
    _sock2 = socket(9999)
    _sock3 = socket(9999)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.close(lsock)
  end
  
  test 'accepting pauses, restarts in link exit ' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    sock1 = socket(9999)
    sock2 = socket(9999)
    sock3 = socket(9999)
    _sock4 = socket(9999)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.send(sock1, "exit")
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.send(sock2, "exit")
    socket_ack(sock3)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.close(lsock)
  end
  
  test 'accepting pauses, restarts after connection release' do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    _sock1 = socket(9999)
    sock2 = socket(9999)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    send pid, {Ahab.Supervisor, {self, nil}, :release_connection}
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.close(lsock)
  end
  
  test "noop on unimplemented supervisor call" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    resp = Supervisor.restart_child(pid, 'foobar')
    assert resp == {:error, :'not implemented'}
    :gen_tcp.close(lsock)
  end
  
  test "count_children/1, worker" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    socket = socket(9999)
    socket_ack(socket)
    assert %{active: 1, specs: 1, supervisors: 0, workers: 1} == Supervisor.count_children(pid)
    :gen_tcp.close(lsock)
  end
  
  test "count_children/1, supervisor" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: supervisor(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    socket = socket(9999)
    socket_ack(socket)
    assert %{active: 1, specs: 1, supervisors: 1, workers: 0} == Supervisor.count_children(pid)
    :gen_tcp.close(lsock)
  end
  
  test "consistent count_children/1 and count_connections" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    sock1 = socket(9999)
    sock2 = socket(9999)
    socket_ack(sock1)
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 2}
    assert %{active: 2, specs: 1, supervisors: 0, workers: 2} == Supervisor.count_children(pid)
    :gen_tcp.close(lsock)
  end

  test "count_children/1, release_connection" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    sock1 = socket(9999)
    sock2 = socket(9999)
    socket_ack(sock1)
    socket_ack(sock2)
    send pid, {Ahab.Supervisor, {self, nil}, :release_connection}
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    assert %{active: 2, specs: 1, supervisors: 0, workers: 2}  == Supervisor.count_children(pid)
    :gen_tcp.send(sock2, "exit")
    :timer.sleep(100)
    assert %{active: 1, specs: 1, supervisors: 0, workers: 1}  == Supervisor.count_children(pid)
    :gen_tcp.close(lsock)
  end

  test ":sys.statistics/2" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], []),
      debug: [:statistics]
    ]
    {:ok, pid} = acceptor(opts)
    _sock = socket(9999)
    {:ok, stats} = :sys.statistics(pid, :get)
    reductions = stats[:reductions]
    {:ok, stats} = :sys.statistics(pid, :get)
    assert stats[:reductions] > reductions 
    :gen_tcp.close(lsock)
  end

  test ":sys.get_status/1" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    parent = self
    s =  %Ahab.Supervisor{
      child_type: :worker,
      mfa: {Ahab.TestModule, :start_link, []},
      lsocket: lsock,
      max_connections: 1,
      dbg: [],
      parent: parent,
      timeout: 5000}
    assert {:status, ^pid, {:module, Ahab.Supervisor}, info} = :sys.get_status(pid)
    assert [process_dict, :running, ^parent, [], status] = info
    [conn_count, state] = status
    assert [conn_count, %{state|ref: nil}] == [0, s]
    assert ["$ancestors": ancestors, 
            "$initial_call": {Ahab.Supervisor, :init, 2}] = process_dict
    assert ancestors == [parent]
    :gen_tcp.close(lsock)
  end

  test ":sys.terminate/2 normal" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    ref = Process.monitor(pid)
    assert :sys.terminate(pid, :normal) == :ok
    assert_receive {:DOWN, ^ref, _, _, :normal}
    :gen_tcp.close(lsock)
  end

  test ":sys.change_code/4" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    assert :sys.suspend(pid) == :ok
    assert :sys.change_code(pid, __MODULE__, nil, nil) == :ok
    assert :sys.resume(pid) == :ok
    sock1 = socket(9999)
    socket_ack(sock1)
    send pid, {Ahab.Supervisor, {self, make_ref}, :count_connections}
    assert_receive {:count_connections, {^pid, _tag}, 1}
    :gen_tcp.close(lsock)
  end

  test ":sys.replace_state/2" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    s =  %Ahab.Supervisor{
      child_type: :worker,
      mfa: {Ahab.TestModule, :start_link, []},
      lsocket: lsock,
      max_connections: 1,
      dbg: [],
      parent: self,
      timeout: 5000}
    state = :sys.get_state(pid)
    :sys.replace_state(pid, fn(_) -> [30, s] end)
    nstate = :sys.get_state(pid)
    assert state != nstate
    assert [30, s] == nstate
    :gen_tcp.close(lsock)
  end

  test ":sys.get_state/1" do
    lsock = lsocket(9999)
    opts = [
      maximum_connections: 1, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = acceptor(opts)
    s =  %Ahab.Supervisor{
      child_type: :worker,
      mfa: {Ahab.TestModule, :start_link, []},
      lsocket: lsock,
      dbg: [],
      max_connections: 1,
      parent: self,
      timeout: 5000}
    [0, rs] = :sys.get_state(pid)
    assert s == %{rs|ref: nil}
    :gen_tcp.close(lsock)
  end

  # Helpers

  defp acceptor(opts) do
    opts
    |> Keyword.put_new(:number_of_acceptors, 1)
    |> Ahab.parse_opts
    |> Ahab.Supervisor.start_link
  end

  defp lsocket(port) do
    sock_opts = [:binary, packet: :raw, active: false, reuseaddr: true]
    {:ok, socket} = :gen_tcp.listen(port, sock_opts)
    socket
  end

  defp socket(port) do
    sock_opts = [:binary, packet: :raw, active: false, reuseaddr: true]
    {:ok, socket} = :gen_tcp.connect('0.0.0.0', port, sock_opts)
    socket
  end

  defp socket_ack(socket) do
    :gen_tcp.send(socket, "sleep")
    :gen_tcp.recv(socket, 0)
  end
end
