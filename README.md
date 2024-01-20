
# Airline Seat Reservation

COM3026 Distributed Systems 2023/24  
Nirmal Bhandari, Paul Latham

## Service API

The service implements an API of the following functions:

### 1. ``get_all_seats(r)``
> This function takes the reservation server PID ‘r’ and computes the status of all seats on the airline. Upon success, this function returns all seat numbers split into two groups, reserved and unreserved. Upon timeout, ``:timeout`` is returned.
### 2. ``book(r, seat_no)``
> This function reserves the seat seat_no. The value ‘r’ is the PID of the reservation server. This function returns ``:ok`` if the seat is successfully booked, or ``:fail`` if the reservation is unsuccessful. Upon timeout, ``:timeout`` is returned.
### 3. ``unbook(r, seat_no)``
> This function un-reserves the seat seat_no. The value ‘r’ is the PID of the reservation server. This function returns ``:ok`` if the seat is successfully unreserved, or ``:fail`` if the operation is unsuccessful. Upon timeout, ``:timeout`` is returned.


## Usage Instructions



## Assumptions

The system does not incorporate user accounts. Assume that, from a business perspective, the only user who unbooks a seat, is the same user who booked the seat originally.

## Properties

#### Safety Properties

- A booked seat cannot be booked.
- An unbooked seat cannot be unbooked.
- At all times, the number of available (unreserved, unbooked) seats is equal to the total number of seats minus the number of unavailable (reserved, booked).
- ...

#### Liveness Properties

- An instance eventually decides given ….
