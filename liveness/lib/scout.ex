# Adam Alilou (aa1320)

defmodule Scout do
  def start(config, leader, acceptors, b) do
    waitfor = acceptors

    self = %{
      config: config,
      leader: leader,
      acceptors: acceptors,
      ballot_num: b,
      waitfor: waitfor,
      pvalues: MapSet.new()
    }

    for a <- self.acceptors do
      send(a, {:p1a, self(), b})
    end

    next(self)
  end

  def next(self) do
    receive do
      {:p1b, a, b1, r} ->
        if ballot_eq(b1, self.ballot_num) do
          self = %{self | waitfor: List.delete(self.waitfor, a)}
          self = %{self | pvalues: MapSet.put(self.pvalues, r)}

          # The current ballot number has been adopted by the majority of the acceptors
          if length(self.waitfor) < (length(self.acceptors) + 1) / 2 do
            send(self.leader, {:ADOPTED, self.ballot_num, self.pvalues})
            send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
          else
            next(self)
          end
        else
          # I have received and adopted a different (larger) ballot number to the one I've been sent
          send(self.leader, {:PREEMPTED, b1})
          send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
        end
    end
  end

  defp ballot_eq(ballot1, ballot2) do
    {a1, b1, _, _} = ballot1
    {a2, b2, _, _} = ballot2

    a1 == a2 and b1 == b2
  end
end
