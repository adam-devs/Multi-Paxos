defmodule OldReplica do
  def start(leaders, initial_state) do
    self = %{
      state: initial_state,
      leaders: leaders,
      slot_in: 1,
      slot_out: 1,
      requests: MapSet.new(),
      proposals: MapSet.new(),
      decisions: MapSet.new()
    }

    self |> next
  end

  def propose(self) do
    # actually a while loop
    if slot_in < slot_out + window and MapSet.member?(requests, c_) do
      if MapSet.member?(decisions, {slot_in - window, {_, _, op}}) and isreconfig(op) do
        leaders = op.leaders
      end

      if !MapSet.member(decisions, {slot_in, _}) do
        self = %{self | requests: MapSet.difference(requests, MapSet.new(c_))}
        self = %{self | proposals: MapSet.union(proposals, MapSet.new({slot_in, c_}))}

        for leader <- leaders do
          send(leader, {:propose, slot_in, c_})
        end
      end

      self |> propose
    end
  end

  def perform({k, cid, op}) do
    # TODO: write function
  end

  def next(self) do
    receive do
      {:request, c} ->
        self = %{self | requests: MapSet.put(self.requests, c)}

      {:decision, s, c} ->
        self = %{self | decisions: MapSet.put(self.decisions, {s, c})}
        # TODO: in while loop
        if MapSet.member?(proposals, {slot_out, c__}) do
          self = %{self | MapSet.delete(proposals, {slot_out, c__})}

          if c__ != c_ do
            self = %{self | MapSet.put(requests, c__)}
          end
        end

        c_ |> propose(perform(c_))
    end

    self |> propose
  end
end
