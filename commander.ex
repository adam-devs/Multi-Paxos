# Adam Alilou (aa1320)

defmodule Comdfmander do
  def start(config, leader, acceptors, replicas, msg) do
    self = %{
      config: config,
      leader: leader,
      acceptors: acceptors,
      replicas: replicas,
      msg: msg,
      #    msg : {b, s, c},
      waitfor: acceptors
    }

    for a <- self.acceptors do
      send(a, {:p2a, self(), msg})
    end

    next(self)
  end

  # @spec next(map) :: no_return
  def next(self) do
    {_b, s, c} = self.msg

    receive do
      {:p2b, a, b_} ->
        if b_ == self.b do
          self = %{self | waitfor: MapSet.delete(self.waitfor, a)}

          if length(self.waitfor) < length(self.acceptors) / 2 do
            for r <- self.replicas do
              send(r, {:decision, s, c})
              send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
            end
          end
        else
          send(self.leader, {:preempted, b_})
          send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
        end
    end

    next(self)
  end
end
