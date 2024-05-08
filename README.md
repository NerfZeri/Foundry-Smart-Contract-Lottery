# Proveable Random Raffle Contracts

# About

this code is to create a proveably random smart contracty lottery.

# What we want to do?

1. Users can enter by paying for a ticket
   1. The ticket fees are going to go to the winner during the draw
2. After X period of time, the lottery will automatically draw a winner
   1. this will be done progmatically
3. Using Chainlink VRF & Chainlink automation
   1. CHainlink VRF -> Randomness
   2. Chainlink Austomation -> Time based trigger.
   

# Notes

The project was made using VRFv2 coordinator but the current chainlink subscription is VRFv2.5.
the VRF v2.5 subscription ID requires a uint256 so wont intregrate with the uint64 coded into the V2 module.