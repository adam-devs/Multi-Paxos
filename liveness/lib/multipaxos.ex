# distributed algorithms, n.dulay 30 jan 2023
# coursework, paxos made moderately complex

defmodule Multipaxos do
  def start do
    config = Configuration.node_init()
    start(config.start_function, config)
  end

  defp start(:cluster_wait, _), do: :skip

  defp start(:cluster_start, config) do
    config = Configuration.node_info(config, "Multipaxos")
    Debug.starting(config)
    # spawn monitoring process and add its process-id to config
    monitor = spawn(Monitor, :start, [config])
    config = Map.put(config, :monitor, monitor)

    Debug.map(config, config)

    for server_num <- 1..config.n_servers do
      Node.spawn(:"server#{server_num}_#{config.node_suffix}", Server, :start, [
        config,
        server_num,
        self()
      ])
    end

    # for

    # receive process-ids of each server's replica, acceptor and leader
    server_modules =
      for _ <- 1..config.n_servers do
        receive do
          {:MODULES, r, a, l} -> {r, a, l}
        end
      end

    # for

    {replicas, acceptors, leaders} = Helper.unzip3(server_modules)

    for replica <- replicas do
      send(replica, {:BIND, leaders})
    end

    for leader <- leaders do
      send(leader, {:BIND, acceptors, replicas})
    end

    for client_num <- 1..config.n_clients do
      Node.spawn(:"client#{client_num}_#{config.node_suffix}", Client, :start, [
        config,
        client_num,
        replicas
      ])
    end

    # for
  end

  # start
end

# Multipaxos
