# Adam Alilou (aa1320)

defmodule Commander do
  def start(config, leader, acceptors, replicas, pvalue) do
    waitfor = acceptors

    self = %{
      config: config,
      leader: leader,
      waitfor: waitfor,
      acceptors: acceptors,
      replicas: replicas,
      pvalue: pvalue
    }

    for acceptor <- acceptors do
      send(acceptor, {:p2a, self(), pvalue})
    end

    next(self)
  end

  def next(self) do
    {b1, s, c} = self.pvalue

    receive do
      {:p2b, a, b2} ->
        if ballot_eq(b2, b1) do
          self = %{self | waitfor: List.delete(self.waitfor, a)}

          if length(self.waitfor) < (length(self.acceptors) + 1) / 2 do
            for r <- self.replicas do
              send(r, {:DECISION, s, c})
            end

            send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
          else
            next(self)
          end
        else
          send(self.leader, {:PREEMPTED, b2})
          send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
        end
    end
  end

  defp ballot_eq(ballot, ballot2) do
    {a1, b1} = ballot
    {a2, b2} = ballot2

    a1 == a2 and b1 == b2
  end
end
