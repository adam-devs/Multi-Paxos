# Adam Alilou (aa1320)

import List

defmodule Replica do
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

  defp propose(self) do
    # Since propose is called from next() if the conditions of the 'while loop' aren't met, go to next
    if self.slot_in >= self.slot_out + self.config.window_size or MapSet.size(self.requests) == 0 do
      next(self)
    end

    # If the command is within the window and is a reconfiguration command the apply the reconfiguration
    self = attempt_reconfig(self)

    slot = self.slot_in

    qualifying_decisions =
      for {^slot, _c} = decision <- self.decisions do
        decision
      end

    if length(qualifying_decisions) == 1 do
      self = %{self | slot_in: self.slot_in + 1}
      next(self)
    end

    c = first(MapSet.to_list(self.requests))

    for l <- self.leaders do
      send(l, {:PROPOSE, self.slot_in, c})
    end

    self = %{self | requests: MapSet.delete(self.requests, c)}
    self = %{self | proposals: MapSet.put(self.proposals, {self.slot_in, c})}
    self = %{self | slot_in: self.slot_in + 1}
    # 'While loop' restarts
    propose(self)
  end

  defp attempt_reconfig(self) do
    slot = self.slot_in - self.config.window_size

    reconfig_decisions =
      for {^slot, {_, _, op}} <- self.decisions,
          isreconfig(op) do
        op
      end

    if length(reconfig_decisions) == 1 do
      self = %{self | leaders: MapSet.put(self.leaders, first(reconfig_decisions).leaders)}
      self
    else
      self
    end
  end

  defp isreconfig(op) do
    # Is op a command to reconfigure the leaders
    case op do
      %{leaders: _leaders} -> true
      _ -> false
    end
  end

  defp perform(self, {k, cid, op}) do
    c = {k, cid, op}

    performed =
      for {s, ^c} <- self.decisions, s < self.slot_out do
        s
      end

    self =
      if length(performed) == 0 or isreconfig(op) do
        send(k, {:CLIENT_RESPONSE, cid, c})
        send(self.database, {:EXECUTE, op})

        self
      else
        self
      end

    self = %{self | slot_out: self.slot_out + 1}
    self
  end

  def next(self) do
    self =
      receive do
        {:CLIENT_REQUEST, c} ->
          send(self.config.monitor, {:CLIENT_REQUEST, self.config.node_num})
          self = %{self | requests: MapSet.put(self.requests, c)}
          self

        {:DECISION, s, c} ->
          self = %{self | decisions: MapSet.put(self.decisions, {s, c})}
          # While we have a command with slot_out in decisions
          self = while_decision(self)
          self

        _else ->
          self
      end

    propose(self)
  end

  defp while_decision(self) do
    slot_out = self.slot_out

    qualifying_decisions =
      for {^slot_out, _c} = d <- self.decisions, into: MapSet.new() do
        d
      end

    if MapSet.size(qualifying_decisions) > 0 do
      {slot_out, c} = first(MapSet.to_list(qualifying_decisions))

      qualifying_proposals =
        for {^slot_out, _c} = proposal <- self.proposals do
          proposal
        end

      if length(qualifying_proposals) > 1 do
        Process.exit(self(), :normal)
      end

      self =
        if length(qualifying_proposals) == 1 do
          {slot_out, c2} = first(qualifying_proposals)
          self = %{self | proposals: MapSet.delete(self.proposals, {slot_out, c2})}

          # If we have a proposal in the same slot as this decision, move it to requests
          self =
            if c != c2 do
              self = %{self | requests: MapSet.put(self.requests, c2)}
              self
            else
              self
            end

          self
        else
          self
        end

      self = perform(self, c)
      self = while_decision(self)
      self
    else
      self
    end
  end
end
