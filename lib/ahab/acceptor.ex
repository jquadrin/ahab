defmodule Ahab.Acceptor do
  @moduledoc false

  # Private API

  def do_accept(conn_count, %{lsocket: socket} = s) do
    case :prim_inet.async_accept(socket, -1) do
      {:ok, ref} -> {conn_count, %{s|ref: ref}}
      {:error, ref} ->
        reason = :inet.format_error(ref)
        error({:no_accept, reason}, s)
        {conn_count, s}
    end
  end

  def configure_socket(socket, %{lsocket: lsocket}) do
    :inet_db.register_socket(socket, :inet_tcp)
    case :prim_inet.getopts(lsocket, []) do
      {:ok, opts} -> :prim_inet.setopts(socket, opts)
      {:error, reason} ->
        error({:close_socket, reason}, socket)
        {:error, reason}
    end
  end

  def transfer_socket(socket, pid) do
    case :gen_tcp.controlling_process(socket, pid) do
      :ok -> 
        send pid, {:ack, socket}
      {:error, reason} ->
        error({:close_socket, reason}, socket)
        send pid, {:no_ack, :error, reason}
    end
  end

  def tentative_accept(:accept_error, conn_count, s), do: do_accept(conn_count, s)
  def tentative_accept(:accept_next, conn_count, %{max_connections: max_connections} = s) do
    case acceptor_status(conn_count, max_connections) do
      :ok -> do_accept(conn_count, s)
      :paused -> {conn_count, %{s|should_accept: false}}
    end
  end
  def tentative_accept(_, conn_count, %{should_accept: should_accept} = s) 
    when should_accept, do: {conn_count, s}
  def tentative_accept(_, conn_count, %{max_connections: max_connections} = s) do
    case acceptor_status(conn_count, max_connections) do
      :ok -> do_accept(conn_count, s)
      :paused -> {conn_count, s}
    end
  end 

  defp acceptor_status(conn_count, max_connections) 
    when conn_count < max_connections, do: :ok
  defp acceptor_status(conn_count, max_connections) 
    when conn_count == max_connections, do: :paused

  def error({:inet_accept, reason}, conn_count, %{lsocket: lsocket, ref: ref} = s) do
    case reason do
      :emfile -> 
        error({:no_accept, reason}, conn_count, s) 
        msg = {:inet_async, lsocket, ref, {:error, :'emfile delay'}}
        Process.send_after(self, msg, 200)
        {conn_count, s}
      :'emfile delay' ->
        tentative_accept(:accept_error, conn_count, s)
      _ -> 
        error({:no_accept, reason}, conn_count, s) 
        tentative_accept(:accept_error, conn_count, s)
    end
  end
  def error({:no_accept, reason}, conn_count, %{lsocket: socket} = s) do
    :error_logger.format(
      '** Acceptor error in ~p~n' ++
      '** Accept on socket ~p paused until next call~n' ++
      '** Reason for pause == ~p~n', [self, socket, reason])
    {conn_count, s}
  end
  def error({:close_socket, reason}, socket) do
    :gen_tcp.close(socket)
    :error_logger.format(
      '** Acceptor error in ~p~n' ++
      '** Socket ~p closed~n' ++
      '** Reason for close == ~p~n', [self, socket, {reason, System.stacktrace()}])
  end


  ## API Helpers

  def init_ack do
    receive do 
      {:ack, socket} -> {:ok, socket} 
      {:no_ack, :error, reason} -> {:error, reason}
    end
  end

  def count_connections(pool_pid) do
    pids = 
      Supervisor.which_children(pool_pid)
      |> Enum.map(fn {_, pid, _, _} -> pid end)
    count_connections(pids, length(pids), 0)
  end
  def count_connections([pid|pids], pid_count, 0) do 
    tag = Process.monitor(pid)
    send pid, {Ahab.Supervisor, {self, tag}, :count_connections}
    count_connections(pids, pid_count, 0)
  end
  def count_connections([], 0, acc), do: acc
  def count_connections([], pid_count, acc) do
    acc = 
      receive do 
        {:count_connections, {_pid, tag}, count} -> 
          Process.demonitor(tag)
          acc + count 
        {:'DOWN', _, :process, _pid, _} -> acc 
      end
    count_connections([], pid_count - 1, acc)
  end

  def release_connection(acceptor_pid) do
    send acceptor_pid, {Ahab.Supervisor, {self, nil}, :release_connection}
  end
end
