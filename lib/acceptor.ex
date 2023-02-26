# Adam Alilou (aa1320)

defmodule Acceptor do
  def start(config) do
    self = %{
      config: config,
      ballot_num: {-1, 0},
      accepted: MapSet.new()
    }

    next(self)
  end

  defp next(self) do
    self =
      receive do
        {:p1a, leader, b} ->
          # {x1, y1} = b
          # {x2, y2} = b
          # IO.puts("BIG NEWS b: #{x1},#{y1}| ballot_num:#{x2},#{y2} ")

          self =
            if b > self.ballot_num do
              self = %{self | ballot_num: b}
              self
            else
              self
            end

          send(leader, {:p1b, self(), self.ballot_num, self.accepted})
          self

        {:p2a, leader, {b, s, c}} ->
          self =
            if b == self.ballot_num do
              self = %{self | accepted: MapSet.put(self.accepted, {b, s, c})}
              self
            else
              self
            end

          send(leader, {:p2b, self(), self.ballot_num})
          self
      end

    next(self)
  end
end
