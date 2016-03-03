defmodule Ahab.Test do
  use ExUnit.Case, async: false

  import Supervisor.Spec

  setup_all do
    {:ok, _apps} = Application.ensure_all_started(:logger) 
    Logger.remove_backend(:console, [flush: true])
    on_exit(fn() -> Logger.add_backend(:console, [flush: true]) end)
  end

  test "start_link/1" do
    lsock = lsocket(9999)
    opts = [
      number_of_acceptors: 1,
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    assert :proc_lib.translate_initial_call(pid) == {:supervisor, Ahab, 1}
    [{_, acceptor_pid, _, _}] = Supervisor.which_children(pid)
    assert Process.info(pid, :links) == {:links, [self, acceptor_pid]}
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    :gen_tcp.close(lsock)
  end

  test "start_link/1, register :local" do
    lsock = lsocket(9999)
    opts = [
      name: __MODULE__,
      number_of_acceptors: 1,
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    assert Process.whereis(__MODULE__) == pid
    assert [{{__MODULE__, 1}, _, _, _}] = Supervisor.which_children(pid)
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    :gen_tcp.close(lsock)
  end

  test "start_link/1, register :global" do
    lsock = lsocket(9999)
    opts = [
      name: {:global, {__MODULE__, :global}},
      number_of_acceptors: 1,
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    assert :global.whereis_name({__MODULE__, :global}) == pid
    assert [{{{:global, {Ahab.Test, :global}}, 1}, _, _, _}] = Supervisor.which_children(pid)
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    :gen_tcp.close(lsock)
  end

  test "start_link/1, register :via" do
    lsock = lsocket(9999)
    opts = [
      name: {:via, :global, {__MODULE__, :via}},
      number_of_acceptors: 1,
      maximum_connections: 10, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    assert :global.whereis_name({__MODULE__, :via}) == pid
    assert [{{{:via, :global, {__MODULE__, :via}}, 1}, _, _, _}] = Supervisor.which_children(pid)
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    :gen_tcp.close(lsock)
  end
 
  test "children/1" do
    lsock = lsocket(9999)
    opts = [
      name: :foobar,
      number_of_acceptors: 4,
      maximum_connections: 12, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    assert [{{:foobar, 4}, _, _, _},
            {{:foobar, 3}, _, _, _},
            {{:foobar, 2}, _, _, _},
            {{:foobar, 1}, _, _, _}] = Supervisor.which_children(pid)
    :gen_tcp.close(lsock)
  end

  test "connection_limits/2, evenly divisible" do
    lsock = lsocket(9999)
    opts = [
      name: :foobar,
      number_of_acceptors: 4,
      maximum_connections: 12, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    assert {:ok, {_strategy,
             [{{_, 1}, {_, _, [[maximum_connections: 3, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 2}, {_, _, [[maximum_connections: 3, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 3}, {_, _, [[maximum_connections: 3, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 4}, {_, _, [[maximum_connections: 3, socket: _, child_spec: _]]}, _, _, _, _}]
            }} = Ahab.init(opts)

    :gen_tcp.close(lsock)
  end

  test "connection_limits/2, not evenly divisble" do
    lsock = lsocket(9999)
    opts = [
      name: :foobar,
      number_of_acceptors: 4,
      maximum_connections: 9, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    assert {:ok, {_,
             [{{_, 1}, {_, _, [[maximum_connections: 2, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 2}, {_, _, [[maximum_connections: 2, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 3}, {_, _, [[maximum_connections: 2, socket: _, child_spec: _]]}, _, _, _, _},
              {{_, 4}, {_, _, [[maximum_connections: 3, socket: _, child_spec: _]]}, _, _, _, _}]
            }} = Ahab.init(opts)
    :gen_tcp.close(lsock)
  end

  test "connections/1" do
    lsock = lsocket(9999)
    opts = [
      number_of_acceptors: 4,
      maximum_connections: 9, 
      socket: lsock,
      child_spec: worker(Ahab.TestModule, [], [])
    ]
    {:ok, pid} = Ahab.start_link(opts)
    _sock1 = socket(9999)
    _sock2 = socket(9999)
    _sock3 = socket(9999)
    _sock4 = socket(9999)
    :timer.sleep(100)
    assert 4 == Ahab.connections(pid)
    Process.flag(:trap_exit, true)
    Process.exit(pid, :kill)
    :gen_tcp.close(lsock)
  end
 
 
  # Helpers

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
end
