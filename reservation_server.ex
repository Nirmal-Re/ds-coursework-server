defmodule ReservationServer do

  def start(name, processes, seats \\ nil) do
      pid = spawn(ReservationServer, :init, [name, processes, seats])
      pid = case :global.re_register_name(name, pid) do
          :yes -> pid
          :no  -> nil
      end
      IO.puts(if pid, do: "registered #{name} with pid #{inspect pid}", else: "failed to register #{name}")
      pid
  end

  def init(name, processes, seats) do
    Process.register(self(), name)
    start_beb()
    start_eld(processes)
    paxos_pid = start_paxos(processes)
    state = %{
        name: name,
        pax_pid: paxos_pid,
        last_instance: 0,
        pending: {0, nil},
        leader_pax_pid: paxos_pid,
        reserved_seats: MapSet.new(),
        unreserved_seats: (if seats != nil and is_list(seats), do: MapSet.new(seats), else: MapSet.new(1..10))    }
    # Ensures shared destiny (if one of the processes dies, the other one does too)
    run(state)
  end

  defp name_participants(processes, childType) do
    for x <- processes, do: String.to_atom(Atom.to_string(x) <> childType)
  end

  defp get_child_name(childType) do
    {:registered_name, parent} = Process.info(self(), :registered_name)
    String.to_atom(Atom.to_string(parent) <> childType)
  end

  defp start_beb() do
    pid = spawn(BestEffortBroadcast, :init, []) #Spawn a BESTEFFORTBROADCAST instance, capturing its pid
    Process.register(pid, get_child_name("_beb")) # pid is registered globally under the key returned from get_child_name(childType)
    Process.link(pid)
  end

  defp start_eld(participants) do
    child = "_eld"
    name = get_child_name(child);
    participants = name_participants(participants, child)
    pid = spawn(EventualLeaderDetector, :init, [name, participants, self()]) #Spawn a EVENTUALLEADERDETECTOR instance, capturing its pid
    Process.register(pid, get_child_name(child)) # pid is registered globally under the key returned from get_child_name(childType)
    IO.puts("#{inspect name}: #{inspect pid}")
    Process.link(pid)
  end

  defp start_paxos(participants) do
    child = "_paxos"
    name = get_child_name(child);
    participants = name_participants(participants, child)
    pid = spawn(Paxos, :init, [name, participants, self()]) #Spawn a PAXOS instance, capturing its pid
    Process.register(pid, get_child_name(child)) # pid is registered globally under the key returned from get_child_name(childType)
    IO.puts("#{inspect name}: #{inspect pid}")
    Process.link(pid)
    pid
  end

  def paxos_name(parent) do
    String.to_atom(Atom.to_string(parent) <> "_paxos")
  end

    # Get pid of a Paxos instance to connect to
    defp get_paxos_pid(paxos_proc) do
      case :global.whereis_name(paxos_proc) do
              pid when is_pid(pid) -> pid
              :undefined -> raise(Atom.to_string(paxos_proc))
      end
    end

  defp wait_for_reply(_, 0), do: nil
  defp wait_for_reply(r, attempt) do
      msg = receive do
          msg -> msg
          after 1000 ->
              send(r, {:poll_for_decisions})
              nil
      end
      if msg, do: msg, else: wait_for_reply(r, attempt-1)
  end

  def book(r, seat_no) do # This function is invoked when the user first says deposite where r = pid of one of the ReservationServer
      # send(r, {:getState, self()})
      # receive do
      #   {:state, state} ->
      #     if MapSet.member?(state.reserved_seats, seat_no) do
      #       :cancel
      #     else
      #     end
      # end
      send(r, {:book, self(), seat_no})
      case wait_for_reply(r, 5) do
        {:cancel} -> :cancel
        {:book_ok} -> :ok
        {:book_failed} -> book(r, seat_no)
        {:abort} -> book(r, seat_no)
        _ -> :timeout
      end
  end

  def unbook(r, seat_no) do
    # send(r, {:getState, self()})
    #   receive do
    #     {:state, state} ->
    #       if !MapSet.member?(state.reserved_seats, seat_no) do
    #         :cancel
    #       else
    #       end
    #   end
    send(r, {:unbook, self(), seat_no})
    case wait_for_reply(r, 5) do
      {:cancel} -> :cancel
      {:unbook_ok} -> :ok
      {:ubook_failed} -> unbook(r, seat_no)
      {:abort} -> unbook(r, seat_no)
      _ -> :timeout
    end
  end

  def get_all_seats(r) do
      send(r, {:allSeats, self(), 0})
      case wait_for_reply(r, 5) do
          {:ok} ->
            send(r, {:getState, self()})
            receive do
              {:state, state} ->
                %{unbooked: state.unreserved_seats, booked: state.reserved_seats}
            end
          _ -> :timeout
      end
  end


  def run(state) do
      state = receive do
          {trans, client, _}=t when trans == :book or trans == :unbook or trans == :allSeats->
              state = poll_for_decisions(state)
              if Paxos.propose(state.leader_pax_pid, state.last_instance+1, t, 10000) == {:abort} do #value of t is a log step for exampel, it could be {:deposite, client, 10}
                  send(client, {:abort})
              else
                  %{state | pending: {state.last_instance+1, client}}
              end

          # {:abort, inst} ->
          #     {pinst, client} = state.pending
          #     if inst == pinst do
          #         send(client, {:abort})
          #         %{state | pending: {0, nil}}
          #     else
          #         state
          #     end

          {:poll_for_decisions} ->
              poll_for_decisions(state)

          {:trust, leader_name} ->
              leader_paxos= paxos_name(leader_name)
              leader_paxos_pid = get_paxos_pid(leader_paxos)
              sub_paxos = paxos_name(state.name)
              sub_paxos_pid = get_paxos_pid(sub_paxos)
              IO.puts("TRUST: #{inspect leader_paxos_pid} CURRRENT: #{inspect sub_paxos_pid}")
              %{state | pax_pid: sub_paxos_pid, leader_pax_pid: leader_paxos_pid}

          {:getState, clientPID} ->
            send(clientPID, {:state, state})
            state

          _ -> state
      end
      # IO.puts("REPLICA STATE: #{inspect state}")
      run(state)
  end


  defp poll_for_decisions(state) do
      case Paxos.get_decision(state.pax_pid, i=state.last_instance+1, 1000) do
        {:book, client, seat_no} ->
          state = case state.pending do
              {^i, ^client} ->
                state = if !MapSet.member?(state.reserved_seats, seat_no) and MapSet.member?(state.unreserved_seats, seat_no) do
                  state = %{state | reserved_seats: MapSet.put(state.reserved_seats, seat_no), unreserved_seats: MapSet.delete(state.unreserved_seats, seat_no)}
                  send(elem(state.pending, 1), {:book_ok})
                  %{state | pending: {0, nil}}
                else
                  send(elem(state.pending, 1), {:cancel})
                  %{state | pending: {0, nil}}
                end

              {^i,
              } ->
                state = if !MapSet.member?(state.reserved_seats, seat_no) and MapSet.member?(state.unreserved_seats, seat_no) do
                  state = %{state | reserved_seats: MapSet.put(state.reserved_seats, seat_no), unreserved_seats: MapSet.delete(state.unreserved_seats, seat_no)}
                  send(elem(state.pending, 1), {:book_failed})
                  %{state | pending: {0, nil}}
                else
                  send(elem(state.pending, 1), {:cancel})
                  %{state | pending: {0, nil}}
                end
              _ ->
                state = if !MapSet.member?(state.reserved_seats, seat_no) and MapSet.member?(state.unreserved_seats, seat_no) do
                  %{state | reserved_seats: MapSet.put(state.reserved_seats, seat_no), unreserved_seats: MapSet.delete(state.unreserved_seats, seat_no)}
                else
                  state
                end
          end
          poll_for_decisions(%{state | last_instance: i})

        {:unbook, client, seat_no} ->
          state = case state.pending do
            {^i, ^client} ->
              state = if MapSet.member?(state.reserved_seats, seat_no) do
                state = %{state | reserved_seats: MapSet.delete(state.reserved_seats, seat_no), unreserved_seats: MapSet.put(state.unreserved_seats, seat_no)}
                send(elem(state.pending, 1), {:unbook_ok})
                %{state | pending: {0, nil}}
              else
                send(elem(state.pending, 1), {:cancel})
                %{state | pending: {0, nil}}
              end

              {^i, _} ->
                state = if MapSet.member?(state.reserved_seats, seat_no) do
                  state = %{state | reserved_seats: MapSet.delete(state.reserved_seats, seat_no), unreserved_seats: MapSet.put(state.unreserved_seats, seat_no)}
                  send(elem(state.pending, 1), {:unbook_failed})
                  %{state | pending: {0, nil}}
                else
                  send(elem(state.pending, 1), {:cancel})
                  %{state | pending: {0, nil}}
                end

              _ ->
                state = if MapSet.member?(state.reserved_seats, seat_no) do
                  %{state | reserved_seats: MapSet.delete(state.reserved_seats, seat_no), unreserved_seats: MapSet.put(state.unreserved_seats, seat_no)}
                else
                  state
                end

            end
            poll_for_decisions(%{state | last_instance: i})

          {:allSeats, client, val} ->
              state = case state.pending do
                  {^i, ^client} ->
                      send(elem(state.pending, 1), {:ok})
                      %{state | pending: {0, nil}}
                  _ -> state
              end
              # state = %{state | balance: (if (bal = state.balance - amount) < 0, do: state.balance, else: bal)}
              # IO.puts("\tNEW BALANCE: #{bal}")
              poll_for_decisions(%{state | last_instance: i})
          nil ->
              state
      end
  end

end
