# Modified by Szymon Kubica (sk4520) 18 Feb 2023
import List

defmodule Replica do
  # ____________________________________________________________________ Setters

  defp update_leaders(self, leaders) do
    %{self | leaders: leaders}
  end

  defp increment_slot_in(self) do
    %{self | slot_in: self.slot_in + 1}
  end

  defp increment_slot_out(self) do
    %{self | slot_out: self.slot_out + 1}
  end

  defp add_proposal(self, proposal) do
    %{self | proposals: MapSet.put(self.proposals, proposal)}
  end

  defp remove_proposal(self, proposal) do
    %{self | proposals: MapSet.delete(self.proposals, proposal)}
  end

  defp add_request(self, request) do
    %{self | requests: MapSet.put(self.requests, request)}
  end

  defp remove_request(self, request) do
    %{self | requests: MapSet.delete(self.requests, request)}
  end

  # ____________________________________________________________________________

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
    if self.slot_in >= self.slot_out + self.config.window_size or MapSet.size(self.requests) == 0,
      do: next(self)

    # TODO maybe point of difference here

    self = attempt_reconfig(self)

    if slot_in_already_decided?(self), do: self |> increment_slot_in |> next

    c = get_next_request(self)

    for l <- self.leaders do
      send(l, {:PROPOSE, self.slot_in, c})
    end

    self
    |> remove_request(c)
    |> add_proposal({self.slot_in, c})
    # |> Debug.log("New request proposed: #{inspect(c)} in slot #{self.slot_in}")
    |> increment_slot_in
    |> propose
  end

  defp get_next_request(self) do
    first(MapSet.to_list(self.requests))
  end

  defp slot_in_already_decided?(self) do
    s = self.slot_in
    decisions_for_s = for {^s, _c} = decision <- self.decisions, do: decision

    if length(decisions_for_s) > 1 do
      # self |> Debug.log("Error: Multiple decisions for slot #{s} found", :error)
    end

    length(decisions_for_s) == 1
  end

  defp attempt_reconfig(self) do
    slot = self.slot_in - self.config.window_size

    reconfig_decisions =
      for {^slot, {_client, _cid, command}} <- self.decisions,
          isreconfig?(command),
          do: command

    if length(reconfig_decisions) == 1 do
      self |> update_leaders(first(reconfig_decisions).leaders)
    else
      self
    end
  end

  defp perform(self, {client, cid, op} = command) do
    self =
      if not already_processed?(self, command) or isreconfig?(op) do
        send(self.database, {:EXECUTE, op})
        send(client, {:CLIENT_RESPONSE, cid, command})

        self
      else
        self
      end

    self |> increment_slot_out
  end

  defp already_processed?(self, command) do
    slots_filled = for {s, ^command} <- self.decisions, s < self.slot_out, do: s

    already_processed = length(slots_filled) != 0

    if already_processed,
      do: self

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
        # self
        # |> Debug.log("Error: there can only be one proposal for slot out: #{slot_out}", :error)

        Process.exit(self(), :normal)
      end

      self =
        if length(proposals_for_slot_out) == 1 do
          {slot_out, c2} = first(proposals_for_slot_out)
          self = self |> remove_proposal({slot_out, c2})
          self = if c != c2, do: self |> add_request(c2), else: self

          self
        else
          self
        end

      self
      |> perform(c)
      |> process_pending_decisions
    else
      self
    end
  end

  defp get_pending_decisions(self) do
    slot_out = self.slot_out
    for {^slot_out, _c} = d <- self.decisions, into: MapSet.new(), do: d
  end

  defp get_proposals_for_slot(self, s) do
    for {^s, _c} = proposal <- self.proposals, do: proposal
  end

  defp slot_in_not_decided?(self) do
    slot_in = self.slot_in
    decisions_for_slot_in = for {^slot_in, _c} = decision <- self.decisions, do: decision
    length(decisions_for_slot_in) == 0
  end
end
