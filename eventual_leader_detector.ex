defmodule EventualLeaderDetector do
  @delta 1000
  @delay 5000
  # Init event must be the first
  # one after the component is created
  def init(name, processes, client) do
    state = %{
      name: name,
      processes: processes,
      client: client,
      # timeout in millis
      delta: 5000,
      alive: MapSet.new([name]),
      suspected: MapSet.new(),
      leader: name
    }

    case :global.re_register_name(name, self()) do
      :yes -> self()
      :no -> IO.puts("ERROR")
    end
    IO.puts("registered #{name}: #{inspect(self())}")

    Process.send_after(self(), {:timeout}, state.delta)
    run(state)
  end

  def run(state) do
    state =
      receive do
        {:timeout} ->
          # IO.puts("#{state.name}: #{inspect({:timeout})} #{state.delta}")
          state = adjust_delta(state)
          state = check_and_probe(state, state.processes)
          select_leader(state.alive, state.leader)
          state = %{state | alive: MapSet.new([state.name])}
          Process.send_after(self(), {:timeout}, state.delta)
          state

        {:heartbeat_request, pid} ->
          # IO.puts("#{state.name}: #{inspect({:heartbeat_request, pid})}")
          # if state.name == :p5, do: Process.sleep(@delay)
          send(pid, {:heartbeat_reply, state.name})
          state

        {:heartbeat_reply, name} ->
          # IO.puts("#{state.name}: #{inspect({:heartbeat_reply, name})}")
          # state.alive is wiped clean after check_and_probe function is called. But here it is filled back up again
          %{state | alive: MapSet.put(state.alive, name)}

        {:crash, p} ->
          p_fail = String.to_atom(hd(String.split(Atom.to_string(p), "_")))
          IO.puts("#{state.name}: CRASH detected #{p_fail}")
          state

        {:sus, p} ->
          IO.puts("#{state.name}: SUS detected #{p}")
          state

        {:new_leader, name} ->
          state = %{state | leader: name}
          # IO.puts("#{state.name}: New leader is #{name}")
          leaderName = String.to_atom(hd(String.split(Atom.to_string(name), "_")))
          send(state.client, {:trust, leaderName})
          state
      end

    run(state)
  end

  defp adjust_delta(state) do
    state = %{state | delta: state.delta + calculate_delta_difference(state)}
    # IO.puts(state.delta)
    state
  end

  defp calculate_delta_difference(state) do
    disjoint = MapSet.disjoint?(state.alive, state.suspected)
    # IO.inspect(state.suspected)
    if disjoint, do: 0, else: @delta
  end

  defp check_and_probe(state, []), do: state

  defp check_and_probe(state, [p | p_tail]) do
    state =
      cond do
        p not in state.alive and p not in state.suspected and :global.whereis_name(p) != self() ->
          state = %{state | suspected: MapSet.put(state.suspected, p)}
          send(self(), {:sus, p})
          state

        p in state.alive and p in state.suspected and :global.whereis_name(p) != self() ->
          state = %{state | suspected: MapSet.delete(state.suspected, p)}
          send(self(), {:restored, p})
          state

        true ->
          state
      end

    case :global.whereis_name(p) do
      pid when is_pid(pid) and pid != self() -> send(pid, {:heartbeat_request, self()})
      pid when is_pid(pid) -> :ok
      :undefined -> :ok
    end

    check_and_probe(state, p_tail)
  end

  defp get_max(alive) do
    alive |> MapSet.to_list() |> Enum.max()
  end

  defp select_leader(alive, leader) do
    max = get_max(alive)
    if(!MapSet.member?(alive, leader) or leader < max) do
      send(self(), {:new_leader, max})
    end
  end
end

# procs = [:p1, :p2, :p3]
# pids = Enum.map(procs, fn p -> EventualLeaderDetector.start(p, procs) end)
