# Adam Alilou (aa1320)

defmodule Rfeplica do
  def start(config, database) do
    leaders =
      receive do
        {:BIND, leaders} -> leaders
      end

    self = %{
      config: config,
      database: database,
      leaders: leaders,
      slot_in: 1,
      slot_out: 1,
      requests: MapSet.new(),
      proposals: MapSet.new(),
      decisions: MapSet.new()
    }

    next(self)
  end

  defp next(self) do
    self =
      receive do
        {:CLIENT_REQUEST, c} ->
          # IO.puts("put me out of my misery")
          send(self.config.monitor, {:CLIENT_REQUEST, self.config.node_num})
          self = %{self | requests: MapSet.put(self.requests, c)}
          self

        {:DECISION, s, c} ->
          # send(self.config.monitor, {:CLIENT_REQUEST, self.config.node_num})
          self = %{self | decisions: MapSet.put(self.decisions, {s, c})}

          self = while_decision(self)
          self

        _ ->
          self
          # after
          #   1000 ->
          #     self
      end

    # IO.puts("sizing is hard #{MapSet.size(self.decisions)}")
    propose(self)
  end

  defp propose(self) do
    # IO.puts("first time boo #{MapSet.size(self.decisions)} ??????")

    # while loop
    if self.slot_in < self.slot_out + self.config.window_size and MapSet.size(self.requests) > 0 do
      # Checks if the operation is to reconfigurate the leaders
      self = attempt_reconfig(self)

      # IO.puts("????????? #{MapSet.size(self.decisions)} ??????")
      # wanted = MapSet.filter(self.decisions, fn {slot_in, _c} -> slot_in == self.slot_in end)

      # IO.puts("xxxxxxxxx #{MapSet.size(wanted)} xxxxxx")
      # MapSet.size(decisions) > 0

      self =
        if !decision_with_slot(self) do
          # if !(MapSet.size(wanted) > 0) do
          c = first(MapSet.to_list(self.requests))

          self = %{self | requests: MapSet.delete(self.requests, c)}
          self = %{self | proposals: MapSet.put(self.proposals, {self.slot_in, c})}

          for leader <- self.leaders do
            send(leader, {:propose, self.slot_in, c})
          end

          self
        else
          self
        end

      self = %{self | slot_in: self.slot_in + 1}
      propose(self)
    else
      next(self)
    end
  end

  defp perform(self, {k, cid, op}) do
    self =
      if already_performed(self, {k, cid, op}) or isreconfig(op) do
        self = %{self | slot_out: self.slot_out + 1}
        self
      else
        send(self.database, {:EXECUTE, op})

        {_next, result} = op.state
        # atomic
        # self = %{self | state: next}
        self = %{self | slot_out: self.slot_out + 1}
        # end atomic

        send(k, {:CLIENT_RESPONSE, cid, result})
        self
      end

    self
  end

  defp while_decision(self) do
    IO.puts("do i get here at least")
    # while loop

    {_, c1} =
      first(
        MapSet.to_list(MapSet.filter(self.decisions, fn {slot, _c} -> self.slot_out == slot end))
      )

    {_, c2} =
      first(
        MapSet.to_list(
          MapSet.filter(self.proposals, fn {slot_out, _cc} ->
            self.slot_out == slot_out
          end)
        )
      )

    self =
      if c1 != "null" and c2 != "null" do
        self = %{self | proposals: MapSet.delete(self.proposals, {self.slot_out, c2})}

        if c1 != c2 do
          self = %{self | requests: MapSet.put(self.requests, {self.slot_out, c2})}
          self
        else
          self
        end

        self
      else
        self
      end

    self =
      if MapSet.size(self.decisions) > 0 do
        perform(self, c1)

        self
      else
        self
      end

    self
  end

  defp isreconfig(op) do
    case op do
      %{leaders: _} -> true
      _ -> false
    end
  end

  defp attempt_reconfig(self) do
    s = self.slot_in - self.config.window_size

    operation =
      first(
        MapSet.to_list(
          MapSet.filter(self.decisions, fn {s_, {_b, _s, op}} ->
            s == s_ and isreconfig(op)
          end)
        )
      )

    self =
      if operation != "null" do
        self = %{self | leaders: operation.leaders}
        self
      else
        self
      end

    self
  end

  defp decision_with_slot(self) do
    decisions = MapSet.filter(self.decisions, fn {slot_in, _c} -> slot_in == self.slot_in end)
    MapSet.size(decisions) > 0
  end

  defp already_performed(self, {k, cid, op}) do
    non_empty = MapSet.size(self.decisions) > 0

    contains_command =
      MapSet.size(MapSet.filter(self.decisions, fn {s, {^k, ^cid, ^op}} -> s < self.slot_out end)) >
        0

    non_empty and contains_command
  end

  defp first(x) do
    if length(x) == 0 do
      "null"
    else
      hd(x)
    end
  end
end
