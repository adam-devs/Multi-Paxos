# Adam Alilou (aa1320)

defmodule Leader do
  def start(config) do
    {acceptors, replicas} =
      receive do
        {:BIND, acceptors, replicas} -> {acceptors, replicas}
      end

    self = %{
      config: config,
      acceptors: acceptors,
      replicas: replicas,
      ballot_num: {0, config.node_num},
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
          if !proposal_exists(self, s) do
            self = %{self | proposals: MapSet.put(self.proposals, {s, c})}

            if self.active do
              send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})

              spawn(Commander, :start, [
                self.config,
                self(),
                self.acceptors,
                self.replicas,
                {self.ballot_num, s, c}
              ])

              self
            end

            self
          end

          self

        {:ADOPTED, ^ballot_num, pvals} ->
          # self = %{self | proposals: update(self.proposals, pmax(self.proposals))}
          IO.puts("lets make some commanders #{MapSet.size(self.proposals)}")
          self = update_proposals(self, pmax(pvals))
          IO.puts("lets make some sexy commanders #{MapSet.size(self.proposals)}")

          for {s, c} <- self.proposals do
            IO.puts("you shouldn't see me")
            send(self.config.monitor, {:COMMANDER_SPAWNED, self.config.node_num})

            spawn(Commander, :start, [
              self.config,
              self(),
              self.acceptors,
              self.replicas,
              {self.ballot_num, s, c}
            ])
          end

          self = %{self | active: true}
          self

        {:PREEMPTED, {r_, leader_}} ->
          # {b1, b2} = self.ballot_num
          # IO.puts("getting preempted or what (#{r_},#{leader_}) vs (#{b1},#{b2})")

          self =
            if ballot_gt({r_, leader_}, self.ballot_num) do
              IO.puts("we running it back????")
              self = %{self | active: false}
              self = %{self | ballot_num: {r_ + 1, self()}}

              spawn(Scout, :start, [self.config, self(), self.acceptors, ballot_num])
              send(self.config.monitor, {:SCOUT_SPAWNED, self.config.node_num})
              self
            else
              self
            end

          self
      end

    next(self)
  end

  # defp update(self, pval) do
  #   # TODO: complete function
  #   # proposals
  #   # {s_, c_}

  #   for {s, c} <- self.proposals do
  #   end
  # end

  # Szymon Kubica made the following two functions
  defp update_proposals(self, max_pvals) do
    remaining_proposals =
      for {s, _c} = proposal <- self.proposals,
          not update_exists?(s, max_pvals),
          into: MapSet.new(),
          do: proposal

    %{self | proposals: MapSet.union(max_pvals, remaining_proposals)}
  end

  defp update_exists?(slot_number, pvalues) do
    updates = for {^slot_number, _c} = pvalue <- pvalues, do: pvalue
    length(updates) != 0
  end

  defp pmax(pvalues) do
    for {b, s, c} <- pvalues,
        Enum.all?(
          for {b1, ^s, _c1} <- pvalues,
              do: ballot_lt(b1, b) or ballot_eq(b1, b)
        ),
        into: MapSet.new(),
        do: {s, c}
  end

  # defp pmax(pvalues) do
  #   max = {0, 0, 0}
  #   b_max = {-1, -1}

  #   for {b, s, c} <- pvalues do
  #     if ballot_lt(b_max, b) or ballot_eq(b_max, b) do
  #       b_max = b
  #       max = {b, s, c}
  #     end
  #   end

  #   max
  # end

  defp proposal_exists(self, s) do
    MapSet.size(MapSet.filter(self.proposals, fn {slot, _} -> slot == s end)) > 0
  end

  defp ballot_lt(ballot, ballot_) do
    {a1, b1} = ballot
    {a2, b2} = ballot_

    a1 < a2 or (a1 == a2 and b1 < b2)
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
