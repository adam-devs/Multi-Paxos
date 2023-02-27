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
          # If I've received the ballot_num I was waiting for, remove the acceptor from the list
          self = %{self | waitfor: List.delete(self.waitfor, a)}

          # If I have a majority of acceptors then I can send the replicas the command
          if length(self.waitfor) < (length(self.acceptors) + 1) / 2 do
            for r <- self.replicas do
              send(r, {:DECISION, s, c})
            end

            send(self.config.monitor, {:COMMANDER_FINISHED, self.config.node_num})
          else
            next(self)
          end
        else
          # Tell the leader that I've received a different (must be larger) ballot number
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
