elixirc *.ex
iex -e "processes = [:RS1, :RS2, :RS3]; 
pids = Enum.map(processes, fn(p) -> ReservationServer.start(p, processes) end);"

a = :global.whereis_name(:RS1);
b = :global.whereis_name(:RS2);
c = :global.whereis_name(:RS3);
ReservationServer.book(a, 1);
ReservationServer.book(a, 2);
ReservationServer.get_all_seats(b)