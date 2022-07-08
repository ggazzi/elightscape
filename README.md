# RoomCtrl

This is a controller for smart lights, based on the idea of having multiple rooms, each with a given set of scenes.
It is meant to integrate with Home Assistant and Zigbee2MQTT (the latter serving only for inputs).


## Behaviour

### IKEA Controllers

- Toggle button: the behaviour will vary according to the current (visible) state and the number of clicks
  - When clicked once: if the lights are currently on, they are turned definitively off; if the lights are turned off, they are turned on with a timeout
