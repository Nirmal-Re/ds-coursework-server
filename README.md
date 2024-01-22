
# Airline Seat Reservation

COM3026 Distributed Systems 2023/24  
Nirmal Bhandari, Paul Latham

## Service API

The service implements an API of the following functions:

### 1. ``get_all_seats(r)``
> This function takes the reservation server PID ‘r’ and computes the status of all seats on the airline. Upon success, this function returns all seat numbers split into two groups, reserved and unreserved. Upon timeout, ``:timeout`` is returned.
### 2. ``book(r, seat_no)``
> This function reserves the seat seat_no. The value ‘r’ is the PID of the reservation server. This function returns ``:ok`` if the seat is successfully booked, or ``:cancel`` if the reservation is unsuccessful. Upon timeout, ``:timeout`` is returned.
### 3. ``unbook(r, seat_no)``
> This function un-reserves the seat seat_no. The value ‘r’ is the PID of the reservation server. This function returns ``:ok`` if the seat is successfully unreserved, or ``:cancel`` if the operation is unsuccessful. Upon timeout, ``:timeout`` is returned.


## Usage Instructions

#### 1. Register 3 processes

``processes = [:RS1, :RS2, :RS3]``

#### 2. Start 3 reservation servers

``pids = Enum.map(processes, fn(p) -> ReservationServer.start(p, processes) end)``

#### 3. Rename the servers for ease of use

``a = :global.whereis_name(:RS1)``

``b = :global.whereis_name(:RS2)``

``c = :global.whereis_name(:RS3)``

#### 4. Book seat 1 on server a, seat 2 on server b, and seat 3 on server c

``ReservationServer.book(a, 1)``

``ReservationServer.book(b, 2)``

``ReservationServer.book(c, 3)``

#### 5. Get all seats on all servers

``ReservationServer.get_all_seats(a)``

``ReservationServer.get_all_seats(b)``

``ReservationServer.get_all_seats(c)``

> All servers are synchronised.

#### 6. Try to book seat 1 on server c (attempt a double-booking)

``ReservationServer.book(c, 1)``

> ``:cancel`` is returned.

#### 7. Get all seats on all servers

``ReservationServer.get_all_seats(a)``

``ReservationServer.get_all_seats(b)``

``ReservationServer.get_all_seats(c)``

> All servers are synchronised.

#### 8. Unbook seat 1 on server b

``ReservationServer.unbook(b, 1)``

#### 9. Get all seats on all servers

``ReservationServer.get_all_seats(a)``

``ReservationServer.get_all_seats(b)``

``ReservationServer.get_all_seats(c)``

> All servers are synchronised.

#### 10. Try to unbook an ubooked seat (double "unbooking"

``ReservationServer.unbook(b, 1)``

> ``:cancel`` is returned.

## Assumptions

The system does not incorporate user accounts. Assume that, from a business perspective, the only user who unbooks a seat, is the same user who booked the seat originally.

## Properties

#### Safety Properties

- A booked seat cannot be booked.
- An unbooked seat cannot be unbooked.
- At all times, the number of available (unreserved, unbooked) seats is equal to the total number of seats minus the number of unavailable (reserved, booked).
- 

#### Liveness Properties

- An instance eventually decides up to at most minority of failures
- 
