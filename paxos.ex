defmodule Paxos do
  @doc """
  name = name of this paxos process
  participants = name of participants taking part in this consensus
  """

  def init(name, processes, client) do
    state = %{
      name: name,
      client: client,
      participants: processes,
      instances: MapSet.new([]),
      runningInstances: %{}
    }
    pid = case :global.re_register_name(name, self()) do   # Registers it in the global registry under the name,
      :yes -> self()
      :no -> :error
    end
    IO.puts"Registered Paxos Instance #{name} pid #{inspect pid} #{inspect self()}"
    run(state)
  end

  # Helper functions: DO NOT REMOVE OR MODIFY
    defp get_beb_name() do
      {:registered_name, parent} = Process.info(self(), :registered_name)
      higher_order_parent = String.split(Atom.to_string(parent), "_") |> List.first
      String.to_atom(higher_order_parent <> "_beb")
    end

    defp beb_broadcast(m, dest) do
      BestEffortBroadcast.beb_broadcast(Process.whereis(get_beb_name()), m, dest)
    end


  @doc """
  This is the main meat of the paxos. This where everything will happen
  """
  def run(state) do
      state =
        receive do
          {:consensus, clientPID, inst, value, time} ->
            state = cond do
              (MapSet.member?(state.instances, inst) and state.runningInstances[inst].decided == true) -> #decided is true
                IO.puts("DECISION HAS ALREADY BEEN MADE FOR #{inspect state.name}")
                decidedVal = state.runningInstances[inst].aVal
                send(clientPID, {:decision, decidedVal}) #for return of {decision, v}
                state

              MapSet.member?(state.instances, inst) and state.runningInstances[inst].decided == false -> #instance already exist but decided is false
                state = updateInstance(state, inst, value, clientPID)
                IO.puts("PROPOSER: #{inspect state.name} for re-inst: #{inspect inst}")
                data_msg = {:prepare, state.name, inst, state.runningInstances[inst].myBallot}
                beb_broadcast(data_msg, state.participants)
                state

              !MapSet.member?(state.instances, inst) -> #instance doesn't exist at all
                state = initInstance(state, inst, value, clientPID)
                IO.puts("PROPOSER: #{inspect state.name} for inst: #{inspect inst}")
                data_msg = {:prepare, state.name, inst, state.runningInstances[inst].myBallot}
                beb_broadcast(data_msg, state.participants) #sending :accepts
                state

              true ->
                state
              end
            Process.send_after(self(), {:pid_timeout, inst}, time)
            state


          {:prepared, inst, orignalBallot, aBal, aVal} ->
            instance = state.runningInstances[inst]
            instancePrepareQuorum = instance.prepareQuorum
            IO.puts("Got prepared!")
            state = if (instance.leader == true and instance.decided == false and orignalBallot == instance.myBallot) do
              IO.puts("PREPARED: RECEIVED BY #{inspect state.name}")
              updatedInstancePrepareQuorum = instancePrepareQuorum ++ [{aBal, aVal}]
              instance = %{instance | prepareQuorum: updatedInstancePrepareQuorum}
              state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
              state = if (length(updatedInstancePrepareQuorum) > length(state.participants)/2  and instance.decided == false) do #Once it has received more than half prepared replies
                sendAccepts(state, inst)
              else
                state
              end
              state
            else
              send(self(), {:nack, inst, orignalBallot}) #Added this for the new change
              state
            end
            # state = leaderCheckPrepared(state)
            state

          {:prepare, senderName, inst, ballot} ->

            state = if (!MapSet.member?(state.instances, inst)), do: firstAcceptOrPrepareInst(state, inst, {"", 0}), else: state
            # state = checkCommit(state)
            instance = state.runningInstances[inst]
            greater = greaterThan(ballot, instance.bal)
            state =
              cond do
                greater and instance.decided == false ->
                  IO.puts("[ Prepare Received => sender: #{inspect senderName} receiver: #{inspect state.name}]")
                  instance = %{instance | bal: ballot}
                  state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
                  data_msg = {:prepared, inst, ballot, instance.aBal, instance.aVal}
                  beb_broadcast(data_msg, [senderName])
                  state

                instance.decided == true ->
                  data_msg = {:commited, state.name, inst, instance.aBal, instance.aVal}
                  beb_broadcast(data_msg, [senderName])
                  state

                !greater ->
                  data_msg = {:nack, inst, ballot}
                  beb_broadcast(data_msg, [senderName])
                  state

                true ->
                  state
              end
            state

          {:accept, senderName, inst, bal, val} ->
            state = if (!MapSet.member?(state.instances, inst)), do: firstAcceptOrPrepareInst(state, inst, bal), else: state #if first accept for this instance, it is logged into the state or else orginal state is preserved
            instance = state.runningInstances[inst]
            # bal >= instance.bal
            gte = greaterThanOrEqualTo(bal, instance.bal)
            state =
              cond do
                gte and instance.decided == false ->
                  IO.puts("[sender = #{inspect senderName}] and [receiver = #{inspect state.name}]")
                  instance = %{instance | aBal: bal}
                  instance = %{instance | aVal: val}
                  state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
                  data_msg = {:accepted, inst, bal, val}
                  beb_broadcast(data_msg, [senderName])
                  state

                instance.decided == true ->
                  data_msg = {:commited, state.name, inst, instance.aBal, instance.aVal}
                  beb_broadcast(data_msg, [senderName])
                  state

                !gte ->
                  data_msg = {:nack, inst, bal}
                  beb_broadcast(data_msg, [senderName])
                  state

                true ->
                  state
              end

            state

          {:commited, senderName, inst, bal, val} ->
            state = if (!MapSet.member?(state.instances, inst)), do: firstAcceptOrPrepareInst(state, inst, bal), else: state #if first accept for this instance, it is logged into the state or else orginal state is preserved
            instance = state.runningInstances[inst]

            if (state.name == senderName and instance.leader == true) do
              send(instance.client, {:decision, val})
            end

            if (state.name != senderName and instance.leader == true) do
              send(self(), {:nack, inst, instance.myBallot})
            end

            state = if (instance.decided == false) do
              IO.puts("#{inspect state.name} got commited by #{inspect senderName}")
              instance = %{instance | decided: true}
              instance = %{instance | aBal: bal}
              instance = %{instance | aVal: val}
              participantsWithoutMe = List.delete(state.participants, state.name)
              beb_broadcast({:commited, senderName, inst, bal, val}, participantsWithoutMe)
              %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
            else
              state
            end
            state

          {:accepted, inst, bal, val} ->
            instance = state.runningInstances[inst]
            instanceAcceptQuorum = instance.acceptQuorum
            state = if (instance.leader == true and instance.decided == false and equalTo(bal, instance.myBallot)) do
              updatedInstanceAcceptQuorum = instanceAcceptQuorum ++ [{bal, val}]
              instance = %{instance | acceptQuorum: updatedInstanceAcceptQuorum}
              state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
              state = if (length(updatedInstanceAcceptQuorum) > length(state.participants)/2) do #Once it has received more than half prepared replies
                IO.puts("#{state.name}: REQUIRED AMOUNT ACCEPTED RECEIVED")
                sendCommited(state, inst, bal, val)
              else
                state
              end
              state
            else
              state
            end
            state

          {:nack, inst, ballot} ->
            instance = state.runningInstances[inst]
            state = if (equalTo(instance.myBallot, ballot) and instance.leader == true) do
              IO.puts("NACK REACHED AND APPROVED: #{inspect state.name} #{inspect ballot}")
              instance = %{instance | leader: false}
              instance = %{instance | acceptQuorum: []}
              instance = %{instance | prepareQuorum: []}
              state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
              send(instance.client, {:abort})
              state
            else
              state
            end
            state

          {:get_state, callerPID} ->
            state = checkCommit(state)
            send(callerPID, {:state, state})
            state

          {:pid_timeout, inst} ->
            instance = state.runningInstances[inst]
            if (instance.leader == true and instance.decided == false) do
              send(instance.client, {:timeout})
            end
            state
        end
    # IO.inspect(state)
    run(state)
  end


  def checkCommit(state) do
    state = receive do
      {:commited, senderName, inst, bal, val} ->
        state = if (!MapSet.member?(state.instances, inst)), do: firstAcceptOrPrepareInst(state, inst, bal), else: state #if first accept for this instance, it is logged into the state or else orginal state is preserved
        instance = state.runningInstances[inst]

        if (state.name == senderName and instance.leader == true) do
          send(instance.client, {:decision, val})
        end

        if (state.name != senderName and instance.leader == true) do
          send(self(), {:nack, inst, instance.myBallot})
        end

        # state = if (greaterThanOrEqualTo(bal, instance.aBal)) do
        state = if (instance.decided == false) do
          IO.puts("#{inspect state.name} got commited by #{inspect senderName}")
          instance = %{instance | aBal: bal}
          instance = %{instance | decided: true}
          instance = %{instance | aVal: val}
          participantsWithoutMe = List.delete(state.participants, state.name)
          beb_broadcast({:commited, senderName, inst, bal, val}, participantsWithoutMe)
          %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
        else
          state
        end
        checkCommit(state)

      after
        0 ->
          # No committed message in the mailbox
          state
    end
    state
  end

  @doc """
  This function is here to be invoked by the client.
  pid: pid of an an elixir process running a paxos replica (pid of the process that is the current leader i.e the one running paxos)
  inst: an instance identifier. It is the instance of consensus that the client process is trying to propose to.
  value: propose a value to paxos (identified by pid)
  t: a timeout in milliseconds (This must be returned if no decision is made with in the timeout)
  """
  def propose(pid, inst, value, t) do
    send(pid, {:consensus, self(), inst, value, t})
    return = receive do
      {:abort} ->
        {:abort}

      {:decision, v} ->
        {:decision, v}

      {:timeout} ->
        IO.puts("[ TIMEOUT from paxos ]")
        {:timeout}

      after
        t + 1000->
          IO.puts("[ TIMEOUT from propose]")
          {:timeout}
      end
    return
  end

  @doc """
  This function is here to be invoked by the client
  """
  def get_decision(pid, inst, t) do
    send(pid, {:get_state, self()})
    decision = receive do
      {:state, state} ->
        if(MapSet.member?(state.instances, inst) and state.runningInstances[inst].decided == true) do
          state.runningInstances[inst].aVal
        else
          nil
        end
      after
        t ->
          nil
    end
    decision
  end

  defp newBallot() do
    timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    uniqueID = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    {uniqueID, timestamp}
  end

  defp initInstance(state, inst, val, client) do
    bal = newBallot()
    temp = %{
      leader: true,
      myBallot: bal,
      decided: false,
      bal: {"", 0},
      aBal: {"", 0},
      aVal: nil,
      value: val,
      acceptQuorum: [],
      prepareQuorum: [],
      client: client
    }
    state = %{state | instances: MapSet.put(state.instances, inst)}
    %{state | runningInstances: Map.put(state.runningInstances, inst, temp)}
  end

  defp updateInstance(state, inst, val, client) do
    instance = state.runningInstances[inst]
    newBal = newBallot()
    instance = %{instance | myBallot: newBal}
    instance = %{instance | leader: true}
    instance = %{instance | value: val}
    instance = %{instance | acceptQuorum: []}
    instance = %{instance | prepareQuorum: []}
    instance = %{instance | client: client}
    state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
    state
  end

  defp firstAcceptOrPrepareInst(state, inst, bal) do
    temp = %{
      leader: false,
      myBallot: nil,
      decided: false,
      bal: bal,
      aBal: {"", 0},
      aVal: nil,
      value: nil,
      acceptQuorum: [],
      prepareQuorum: [],
      client: nil
    }
    state = %{state | instances: MapSet.put(state.instances, inst)}
    %{state | runningInstances: Map.put(state.runningInstances, inst, temp)}
  end


  defp sendAccepts(state, inst) do
    instance = state.runningInstances[inst]
    instancePrepareQuorum = instance.prepareQuorum
    # state = if (instance.leader == true and instance.decided == false and length(instancePrepareQuorum) > length(state.participants)/2) do
    state = if (instance.leader == true and instance.decided == false) do
      {_, valueToBeAccepted} = Enum.max_by(instancePrepareQuorum, fn {atom, _value} -> atom end)
      valueToBeAccepted = if (valueToBeAccepted == nil), do: instance.value, else: valueToBeAccepted
      instance = %{instance | prepareQuorum: []}
      state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
      IO.puts("#{inspect state.name}: SEND_ACCEPTS with the value: #{inspect valueToBeAccepted}")
      data_msg = {:accept, state.name, inst, instance.myBallot, valueToBeAccepted}
      beb_broadcast(data_msg, state.participants)
      state
    else
      state
    end
    state
  end

  defp sendCommited(state, inst, bal, val) do
    instance = state.runningInstances[inst]
    instanceAcceptQuorum = instance.acceptQuorum
    state = if (instance.leader == true and instance.decided == false) do
      instance = %{instance | acceptQuorum: []}
      state = %{state | runningInstances: Map.put(state.runningInstances, inst, instance)}
      data_msg = {:commited, state.name, inst, bal, val}
      beb_broadcast(data_msg, state.participants)
      IO.puts("[:COMMITED Broadcast sent from #{inspect state.name} to => #{inspect state.participants}]")
      state
      else
      state
      end
      state
  end

  # ballot > instance.bal
  def greaterThan({pid1, timestamp1}, {pid2, timestamp2}) do
    cond do
      timestamp1 > timestamp2 -> true
      timestamp1 == timestamp2 and pid1 > pid2 -> true
      true -> false
    end
  end

  # bal >= instance.bal
  defp greaterThanOrEqualTo({pid1, timestamp1}, {pid2, timestamp2}) do
    cond do
      timestamp1 > timestamp2 -> true
      timestamp1 == timestamp2 and pid1 > pid2 -> true
      timestamp1 == timestamp2 and pid1 == pid2 -> true
      true -> false
    end
  end

  defp equalTo({pid1, timestamp1}, {pid2, timestamp2}) do
    cond do
      timestamp1 == timestamp2 and pid1 == pid2 -> true
      true -> false
    end
  end

end
