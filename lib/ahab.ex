defmodule Ahab do
  @moduledoc """
  A lightweight, low latency TCP acceptor pool for Elixir.

  This module handles supervision of an acceptor pool and provides support for interfacing 
  with acceptor processes. 
  """

  use Supervisor


  ### API ###
  
  @doc """
  Start a TCP acceptor pool.

  ## Options
  
    * `:name` - Pool supervisor name (default: Ahab);
    * `:maximum_connections` - Maximum number of connections allowed for pool (required);
    * `:number_of_acceptors` - Number of acceptors to receive incoming requests
    and supervise connection processes (required);
    * `:child_spec` - Supervisor specification such as `worker` or `supervisor` (required);
    * `:socket` - TCP listener socket;
    * `:listen_port` - Port number, creates a tcp listening socket. only use if `:socket` 
    is not specified; 
  """
  @spec start_link(Keyword.t) :: {:ok, pid} | {:error, term}
  def start_link(opts) do
    opts = parse_opts(opts)
    Supervisor.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Return the socket transferred to the calling process when
  successfully acknowledged by an acceptor.
  """
  @spec init_ack :: {:ok, port} | {:error, term}
  def init_ack do 
    Ahab.Supervisor.init_ack
  end 

  @doc """
  Return the number of connections currently being served by an 
  acceptor pool.
  """
  @spec connections(pid) :: {:ok, integer}
  def connections(supervisor_pid) do
    Ahab.Supervisor.count_connections(supervisor_pid)
  end

  @doc """
  Release a connection process from an acceptor's supervision.
  """
  @spec release_connection(pid) :: none
  def release_connection(acceptor_pid) do
    Ahab.Supervisor.release_connection(acceptor_pid)
  end

  @doc """
  Return a supervisor child specification for an acceptor pool.
  """
  @spec child_spec(Keyword.t) :: Supervisor.Spec.spec
  def child_spec(opts) do 
    opts = parse_opts(opts)
    supervisor(__MODULE__, [opts], name: opts[:name])
  end


  # Supervisor

  @doc false
  def init(opts) do
    children(opts) |> supervise(strategy: :one_for_all)
  end

  defp children(opts) do
    opts 
    |> children_params
    |> Enum.map(fn {opts, id} ->
         supervisor(Ahab.Supervisor, [opts], id: id) 
       end)
  end

  defp children_params(opts) do
    {name, opts}                = Keyword.pop(opts, :name)
    {number_of_acceptors, opts} = Keyword.pop(opts, :number_of_acceptors)
    {maximum_connections, opts} = Keyword.pop(opts, :maximum_connections)
    connection_limits(number_of_acceptors, maximum_connections)
    |> Enum.map(&Keyword.put(opts, :maximum_connections, &1))
    |> Enum.zip(acceptor_identifiers(name, number_of_acceptors))
  end


  # Helpers

  @doc false
  def parse_opts(opts) do
    opts                = validate_opts(opts)
    name                = Keyword.get(opts, :name, __MODULE__)
    maximum_connections = Keyword.get(opts, :maximum_connections)
    number_of_acceptors = Keyword.get(opts, :number_of_acceptors)
    socket              = Keyword.get(opts, :socket)
    child_spec          = Keyword.get(opts, :child_spec)
    debug               = Keyword.get(opts, :debug, [])

    {_, {m, f, a}, _, shutdown, child_type, _} = child_spec

    [
      name: name,
      maximum_connections: maximum_connections, 
      number_of_acceptors: number_of_acceptors,
      socket: socket,
      mfa: {m, f, a},
      shutdown: shutdown,
      child_type: child_type,
      debug: debug
    ]
  end

  defp validate_opts(opts) do
    required = [:maximum_connections, :number_of_acceptors, :child_spec]
    cond do
      not Enum.all?(required, &Enum.member?(Keyword.keys(opts), &1)) ->
        exit('Missing required parameter(s).')
      Keyword.has_key?(opts, :socket) -> opts
      Keyword.has_key?(opts, :listen_port) -> add_listener_socket(opts) 
      true ->
        exit('Missing socket parameter(s).')
    end
  end

  defp add_listener_socket(opts) do
    sock_opts = [:binary, packet: :raw, active: false, reuseaddr: true]
    {:ok, socket} = :gen_tcp.listen(opts[:listen_port], sock_opts)
    Keyword.put_new(opts, :socket, socket)
  end

  defp connection_limits(number_of_acceptors, maximum_connections) do
    remainder = rem(maximum_connections, number_of_acceptors)
    quotient = div(maximum_connections, number_of_acceptors) |> round
    List.duplicate(0, number_of_acceptors - remainder) ++ List.duplicate(1, remainder)
    |> Enum.map(fn(x) -> x + quotient end) 
  end

  defp acceptor_identifiers(name, number_of_acceptors) do 
    1..number_of_acceptors |> Enum.map(fn(x) -> {name, x} end) 
  end
end
