# Adam Alilou (aa1320)

defmodule Scout do
  def start(config, leader, acceptors, b) do
    waitfor = acceptors

    self = %{
      config: config,
      leader: leader,
      acceptors: acceptors,
      b: b,
      waitfor: waitfor,
      pvalues: MapSet.new()
    }

    # IO.puts("I am feeding the acceptors")

    for a <- self.acceptors do
      send(a, {:p1a, self(), b})
    end

    next(self)
  end

  def next(self) do
    receive do
      {:p1b, a, b_, r} ->
        # {x, y} = b_
        # {x1, y1} = self.b
        # IO.puts("we making progress #{x}, #{y},#{x1}, #{y1}, ")

        if b_ == self.b do
          # IO.puts("on to the next")

          self = %{self | pvalues: MapSet.put(self.pvalues, r)}
          self = %{self | waitfor: List.delete(self.waitfor, a)}

          IO.puts(
            "waitfor (#{length(self.waitfor)}), self.acceptors(#{(length(self.acceptors) + 1) / 2})"
          )

          if length(self.waitfor) < (length(self.acceptors) + 1) / 2 do
            # IO.puts("and for his debut: ADOPTED!!!")
            send(self.leader, {:ADOPTED, self.b, self.pvalues})
            send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
            exit(finished: "adopted")
          else
            next(self)
          end
        else
          send(self.leader, {:PREEMPTED, b_})
          send(self.config.monitor, {:SCOUT_FINISHED, self.config.node_num})
          exit(finished: "preempted")
        end
    end

    next(self)
  end
end
