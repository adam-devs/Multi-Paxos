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

  def next(self) do
    self =
      receive do
        {:CLIENT_REQUEST, c} ->
          send(self.config.monitor, {:CLIENT_REQUEST, self.config.node_num})
          self = %{self | requests: MapSet.put(self.requests, c)}
          self

        {:DECISION, s, c} ->
          self = %{self | decisions: MapSet.put(self.decisions, {s, c})}
          process_pending_decisions(self)

        _unexpected ->
          self
      end

    propose(self)
  end

  defp propose(self) do
    if self.slot_in >= self.slot_out + self.config.window_size or MapSet.size(self.requests) == 0 do
      next(self)
    end

    self = attempt_reconfig(self)

    if slot_in_already_decided?(self) do
      self = %{self | slot_in: self.slot_in + 1}
      next(self)
    end

    c = get_next_request(self)

    for l <- self.leaders do
      send(l, {:PROPOSE, self.slot_in, c})
    end

    self = %{self | requests: MapSet.delete(self.requests, c)}
    self = %{self | proposals: MapSet.put(self.proposals, {self.slot_in, c})}
    self = %{self | slot_in: self.slot_in + 1}
    propose(self)
  end

  defp get_next_request(self) do
    first(MapSet.to_list(self.requests))
  end

  defp slot_in_already_decided?(self) do
    s = self.slot_in

    decisions_for_s =
      for {^s, _c} = decision <- self.decisions do
        decision
      end

    if length(decisions_for_s) > 1 do
    end

    length(decisions_for_s) == 1
  end

  defp attempt_reconfig(self) do
    slot = self.slot_in - self.config.window_size

    reconfig_decisions =
      for {^slot, {_client, _cid, command}} <- self.decisions,
          isreconfig?(command) do
        command
      end

    if length(reconfig_decisions) == 1 do
      self = %{self | leaders: MapSet.put(self.leaders, first(reconfig_decisions).leaders)}
      self
    else
      self
    end
  end

  defp perform(self, {client, cid, op} = command) do
    self =
      if not already_performed(self, command) or isreconfig?(op) do
        send(self.database, {:EXECUTE, op})
        send(client, {:CLIENT_RESPONSE, cid, command})

        self
      else
        self
      end

    self = %{self | slot_out: self.slot_out + 1}
    self
  end

  defp already_performed(self, command) do
    slots_filled =
      for {s, ^command} <- self.decisions, s < self.slot_out do
        s
      end

    already_processed = length(slots_filled) != 0

    if already_processed do
      self
    end

    already_processed
  end

  defp isreconfig?(op) do
    case op do
      %{leaders: _leaders} -> true
      _ -> false
    end
  end

  defp process_pending_decisions(self) do
    decisions_for_slot_out = get_pending_decisions(self)

    if MapSet.size(decisions_for_slot_out) > 0 do
      {slot_out, c} = first(MapSet.to_list(decisions_for_slot_out))

      proposals_for_slot_out = self |> get_proposals_for_slot(slot_out)

      if length(proposals_for_slot_out) > 1 do
        Process.exit(self(), :normal)
      end

      self =
        if length(proposals_for_slot_out) == 1 do
          {slot_out, c2} = first(proposals_for_slot_out)
          self = %{self | proposals: MapSet.delete(self.proposals, {slot_out, c2})}

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
      self = process_pending_decisions(self)
      self
    else
      self
    end
  end

  defp get_pending_decisions(self) do
    slot_out = self.slot_out

    for {^slot_out, _c} = d <- self.decisions, into: MapSet.new() do
      d
    end
  end

  defp get_proposals_for_slot(self, s) do
    for {^s, _c} = proposal <- self.proposals do
      proposal
    end
  end
end
