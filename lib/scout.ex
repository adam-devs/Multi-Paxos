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
        # {x, y} = b1
        # {x1, y1} = self.ballot_num
        # IO.puts("we making progress #{x}, #{y},#{x1}, #{y1}, ")

        if b1 == self.ballot_num do
          self = %{self | waitfor: List.delete(self.waitfor, a)}
          self = %{self | pvalues: MapSet.put(self.pvalues, r)}

          # IO.puts(
          #   "waitfor (#{length(self.waitfor)}), self.acceptors(#{(length(self.acceptors) + 1) / 2})"
          # )

          if length(self.waitfor) < (length(self.acceptors) + 1) / 2 do
            send(self.leader, {:ADOPTED, self.ballot_num, self.pvalues})
            send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
          else
            next(self)
          end
        else
          send(self.leader, {:PREEMPTED, b1})
          send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
        end
    end
  end
end
