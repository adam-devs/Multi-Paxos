# Adam Alilou (aa1320)

defmodule Acceptor do
  def start(config) do
    self = %{
      config: config,
      ballot_num: {-10, -10},
      accepted: MapSet.new()
    }

    next(self)
  end

  def next(self) do
    self =
      receive do
        {:p1a, leader, b} ->
          self =
            if ballot_gt(b, self.ballot_num) do
              self = %{self | ballot_num: b}
              self
            else
              self
            end

          send(leader, {:p1b, self(), self.ballot_num, self.accepted})
          self

        {:p2a, leader, {b, s, c}} ->
          self =
            if ballot_eq(b, self.ballot_num) do
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

  defp ballot_gt(ballot, ballot_) do
    {a1, b1} = ballot
    {a2, b2} = ballot_

    a1 > a2 or (a1 == a2 and b1 > b2)
  end

  defp ballot_eq(ballot, ballot2) do
    {a1, b1} = ballot
    {a2, b2} = ballot2

    a1 == a2 and b1 == b2
  end
end
