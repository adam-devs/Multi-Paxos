# Adam Alilou (aa1320)

defmodule Acceptor do
  def start(config) do
    ballot_num = {0, 0, self()}

    self = %{
      config: config,
      ballot_num: ballot_num,
      accepted: MapSet.new()
    }

    next(self)
  end

  def next(self) do
    self =
      receive do
        {:p1a, l, b} ->
          self =
            if ballot_gt(b, self.ballot_num) do
              self = %{self | ballot_num: b}
              self
            else
              self
            end

          # Send the leader response with the current ballot number and pvalues accepted so far
          send(l, {:p1b, self(), self.ballot_num, self.accepted})
          self

        {:p2a, l, {b, s, c}} ->
          self =
            if ballot_eq(b, self.ballot_num) do
              self = %{self | accepted: MapSet.put(self.accepted, {b, s, c})}
              self
            else
              self
            end

          # Send the leader response with the current ballot number
          send(l, {:p2b, self(), self.ballot_num})
          self
      end

    next(self)
  end

  defp ballot_gt(ballot1, ballot2) do
    {a1, b1, _} = ballot1
    {a2, b2, _} = ballot2

    a1 > a2 or (a1 == a2 and b1 > b2)
  end

  defp ballot_eq(ballot1, ballot2) do
    {a1, b1, _} = ballot1
    {a2, b2, _} = ballot2

    a1 == a2 and b1 == b2
  end
end
