defmodule Ahab.Supervisor do
  @moduledoc false

  defstruct [parent: nil, dbg: nil, lsocket: nil, ref: nil, mfa: nil, 
             child_type: nil, max_connections: nil, timeout: nil, should_accept: true]

  def start_link(opts) do
    :proc_lib.start_link(__MODULE__, :init, [self, opts])
  end

  def init(parent, opts) do
    Process.flag(:trap_exit, true)
    :proc_lib.init_ack(parent, {:ok, self})
    dbg = :sys.debug_options(opts[:debug])

    s = %__MODULE__{parent:           parent, 
                    dbg:              dbg,
                    lsocket:          opts[:socket], 
                    mfa:              opts[:mfa], 
                    child_type:       opts[:child_type], 
                    max_connections:  opts[:maximum_connections], 
                    timeout:          opts[:shutdown]}

    {conn_count, s} = Ahab.Acceptor.do_accept(0, s)
    loop(conn_count, s)
  end

  def loop(conn_count, %{parent: parent, dbg: dbg, lsocket: lsocket, child_type: child_type,
                         ref: ref, mfa: mfa, timeout: timeout, should_accept: should_accept} = s) do
    receive do
      {:inet_async, ^lsocket, ^ref, {:ok, socket}} = ev -> 
        dbg = :sys.handle_debug(dbg, &write_debug/3, should_accept, ev)
        case Ahab.Acceptor.configure_socket(socket, s) do
          :ok -> :ok
          {:error, reason} -> exit({:error, reason}, timeout)
        end
        {conn_count, s} = 
          case spawn_child(s) do
            {:ok, pid} ->
              Ahab.Acceptor.transfer_socket(socket, pid)
              Ahab.Acceptor.tentative_accept(:accept_next, conn_count + 1, s)
            {:error, reason} ->
              Ahab.Acceptor.error({:close_socket, reason}, socket)
              Ahab.Acceptor.tentative_accept(:accept_next, conn_count, s)
          end
        loop(conn_count, %{s|dbg: dbg})
      {:inet_async, ^lsocket, ^ref, {:error, :closed}} -> exit({:error, :closed}, :brutal_kill)
      {:inet_async, ^lsocket, ^ref, {:error, reason}} = ev -> 
        dbg = :sys.handle_debug(dbg, &write_debug/3, should_accept, ev)
        {conn_count, s} = Ahab.Acceptor.error({:inet_accept, reason})
        loop(conn_count, %{s|dbg: dbg})

      {__MODULE__, {from, tag}, :count_connections} ->
        send from, {:count_connections, {self, tag}, conn_count}
        loop(conn_count, s)
      {__MODULE__, {from, _tag}, :release_connection} = ev ->
        dbg = :sys.handle_debug(dbg, &write_debug/3, should_accept, ev)
        Process.unlink(from)
        {conn_count, s} = Ahab.Acceptor.tentative_accept(:release_call, conn_count - 1, s)
        loop(conn_count, %{s|dbg: dbg})

      {:'$gen_call', {from, tag}, :count_children} -> 
        count_children(child_type, from, tag)
        loop(conn_count, s)
      {:'$gen_call', {from, tag}, :which_children} -> 
        which_children(mfa, child_type, from, tag)
        loop(conn_count, s)
      {:'$gen_call', {from, tag}, _} -> 
        send from, {tag, {:error, :'not implemented'}}
        loop(conn_count, s)

      {:EXIT, ^parent, reason} -> terminate(reason, timeout)
      {:EXIT, pid, _reason} = ev -> 
        dbg = :sys.handle_debug(dbg, &write_debug/3, should_accept, ev)
        delete_child(pid)
        {conn_count, s} = Ahab.Acceptor.tentative_accept(:unlink_call, conn_count - 1, s)
        loop(conn_count, %{s|dbg: dbg})
      {:system, from, msg} -> 
        :sys.handle_system_msg(msg, from, parent, __MODULE__, dbg, [conn_count, s])

      msg -> 
        :error_logger.format("Received unexpected message: ~p~n", [msg])
        loop(conn_count, s)
    end
  end

  defp write_debug(dev, {:inet_async, sock, _, msg}, should_accept) do
    [inspect(self), " got event inet_async ", inspect(msg), 
     " with socket: ", inspect(sock), ", should accept: ", inspect(should_accept)] 
    |> write_event(dev)
  end
  defp write_debug(dev, {_, {from, _}, :remove_connection}, should_accept) do
    [inspect(self), " got event remove_connection from ", inspect(from), 
     ", should accept: ", inspect(should_accept)] 
    |> write_event(dev)
  end
  defp write_debug(dev, {:EXIT, pid, reason}, should_accept) do
    [inspect(self), " got event :EXIT from ", inspect(pid), 
     ", reason: ", inspect(reason), ", should accept: ", inspect(should_accept)] 
    |> write_event(dev)
  end
  defp write_event(msg, dev), do: IO.puts(dev, ["*DBG* "|msg])


  def system_continue(_, _, state), do: apply(__MODULE__, :loop, state)
  def system_terminate(reason, _, _, [_, %{timeout: timeout}]), do: terminate(reason, timeout)
  def system_code_change(misc, _, _, _), do: {:ok, misc}
  def system_get_state(state), do: {:ok, state}
  def system_replace_state(replace, state) do
    new_state = replace.(state)
    {:ok, new_state, new_state}
  end

  defp spawn_child(%{mfa: {m, f, a}}) do
    case do_apply(m, f, a) do
      {:ok, pid} -> add_child(pid)
      {:ok, sup_pid, _pid} -> add_child(sup_pid)
      error -> error
    end
  end

  defp add_child(pid) do
    Process.put(pid, :child)
    {:ok, pid}
  end

  defp delete_child(pid) do
    Process.delete(pid) 
  end

  defp do_apply(module, fun, args) do
    try do
      apply(module, fun, args)
    rescue
      e in RuntimeError ->
        {:error, e.message}
      e in UndefinedFunctionError ->
        {:error, e.message}
      msg ->
        reason = {msg, System.stacktrace()}
        {:error, reason}
    end
  end

  defp count_children(:supervisor, to, tag) do
    count = length(Process.get_keys(:child))
    send to, {tag, [{:specs, 1}, {:active, count}, 
                    {:supervisors, count}, {:workers, 0}]}
  end
  defp count_children(:worker, to, tag) do
    count = length(Process.get_keys(:child))
    send to, {tag, [{:specs, 1}, {:active, count}, 
                    {:supervisors, 0}, {:workers, count}]}
  end

  defp which_children({mod, _}, child_type, to, tag) do
    children =  
      Process.get_keys(:child)
      |> Enum.map(fn pid -> {mod, pid, child_type, [mod]} end)
    send to, {tag, children}
  end

  defp exit({:error, reason}, timeout) do
    :error_logger.format(
      '** Supervisor ~p terminating~n' ++
      '** Reason for termination == ~p~n', [self, reason])
    terminate(reason, timeout) 
  end

  def terminate(reason, timeout) do
    child_pids = Process.get_keys(:child)
    case timeout do
      :brutal_kill ->
        Enum.each(child_pids, &Process.exit(&1, :kill))
      :infinity ->
        Enum.each(child_pids, &shutdown_child(&1)) 
        :ok = terminate_loop(length(child_pids))
      _ ->
        Enum.each(child_pids, &shutdown_child(&1)) 
        Process.send_after(self, :kill_all, timeout)
        :ok = terminate_loop(length(child_pids))
    end
    exit(reason)
  end

  def shutdown_child(pid) do
    Process.monitor(pid)
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
  end

  def terminate_loop(0), do: :ok
  def terminate_loop(child_count) do
    receive do
      {:'EXIT', _pid, _reason} -> 
        terminate_loop(child_count)
      {:'DOWN', _, :process, pid, _} ->
        Process.delete(pid)
        terminate_loop(child_count - 1)
      :kill_all ->
        Process.get_keys(:child) 
        |> Enum.each(&Process.exit(&1, :kill))
        :ok
      _ ->
        terminate_loop(child_count)
    end
  end
end
