# Adam Alilou (aa1320)
defmodule Leader do
  def start(config) do
    ballot_num = {0, config.node_num}

    {acceptors, replicas} =
      receive do
        {:BIND, acceptors, replicas} -> {acceptors, replicas}
      end

    self = %{
      config: config,
      ballot_num: ballot_num,
      acceptors: acceptors,
      replicas: replicas,
      active: false,
      proposals: MapSet.new()
    }

    spawn(Scout, :start, [self.config, self(), self.acceptors, self.ballot_num])
    send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})

    next(self)
  end

  def next(self) do
    ballot_num = self.ballot_num

    self =
      receive do
        {:PROPOSE, s, c} ->
          self =
            if(!proposal_exists(self, s)) do
              self = %{self | proposals: MapSet.put(self.proposals, {s, c})}

              if self.active do
                spawn(Commander, :start, [
                  self.config,
                  self(),
                  self.acceptors,
                  self.replicas,
                  {self.ballot_num, s, c}
                ])

                send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})
              end

              self
            else
              self
            end

          self

        {:ADOPTED, ^ballot_num, pvalues} ->
          self = update_proposals(self, pmax(pvalues))

          for {s, c} <- self.proposals do
            spawn(Commander, :start, [
              self.config,
              self(),
              self.acceptors,
              self.replicas,
              {self.ballot_num, s, c}
            ])

            send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})
          end

          self = %{self | active: true}
          self = next(self)
          self

        {:PREEMPTED, {value, _leader} = b} ->
          self =
            if ballot_eq(b, self.ballot_num) do
              self = %{self | active: false}
              {_, leader} = self.ballot_num
              self = %{self | ballot_num: {value + 1, leader}}

              spawn(Scout, :start, [self.config, self(), self.acceptors, self.ballot_num])
              send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})
              self
            else
              self
            end

          self
      end

    next(self)
  end

  # TODO: create versions of the following 3 functions
  defp update_proposals(self, max_pvals) do
    remaining_proposals =
      for {s, _c} = proposal <- self.proposals,
          not update_exists?(s, max_pvals),
          into: MapSet.new() do
        proposal
      end

    %{self | proposals: MapSet.union(max_pvals, remaining_proposals)}
  end

  defp update_exists?(slot_number, pvalues) do
    updates = for {^slot_number, _c} = pvalue <- pvalues, do: pvalue
    length(updates) != 0
  end

  defp pmax(pvalues) do
    for {b, s, c} <- pvalues,
        Enum.all?(
          for {b1, ^s, _c1} <- pvalues do
            ballot_lt(b1, b) or ballot_eq(b1, b)
          end
        ),
        into: MapSet.new() do
      {s, c}
    end
  end

  defp proposal_exists(self, s) do
    MapSet.size(MapSet.filter(self.proposals, fn {slot, _command} -> slot == s end)) > 0
  end

  defp ballot_lt(ballot, ballot_) do
    {a1, b1} = ballot
    {a2, b2} = ballot_

    a1 < a2 or (a1 == a2 and b1 < b2)
  end

  defp ballot_eq(ballot, ballot2) do
    {a1, b1} = ballot
    {a2, b2} = ballot2

    a1 == a2 and b1 == b2
  end
end
