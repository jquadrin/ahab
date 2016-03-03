# Ahab

[![Build Status](https://travis-ci.org/jquadrin/ahab.svg?branch=master)](https://travis-ci.org/jquadrin/ahab)

A lightweight, low latency TCP acceptor pool for Elixir.

Documentation: http://hexdocs.pm/ahab

## Example
```elixir
import Supervisor.Spec

{:ok, lsocket} = :gen_tcp.listen(9999, [:binary, packet: :raw, active: false])

{:ok, pid} = 
  Ahab.start_link([
    number_of_acceptors: 10,
    maximum_connections: 100,
    socket: lsocket,
    child_spec: worker(SomeModule, [])
  ])
  
# You can optionally pass in a port number instead of a socket using `:listen_port`.
```
This creates 10 acceptors with 10 maximum connections allowed for each.

## Specifics

Ahab *only* operates at the TCP layer, for SSL, any client socket can be upgraded using `:ssl.ssl_accept`.

Ahab uses an erlang supervisor child spec for spawning connection-handling child processes.
Child processes must be linked and must return `{:ok, worker_pid}` or `{:ok, supervisor_pid, worker_pid}`.

`Ahab.init_ack/0` returns a client TCP socket. This function should not be called until a process has completely started, as concerns standard OTP behaviours.

## License

Copyright 2016 Joe Quadrino

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
```
    http://www.apache.org/licenses/LICENSE-2.0
```
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
