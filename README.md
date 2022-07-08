# Elightscape

This is a controller for smart lights, built with Elixir.
It is meant to integrate with Home Assistant (doing the actual control of the devices and providing an UI) and Zigbee2MQTT (taking inputs directly from devices).

For now, the configuration is hard-coded for my place.
Eventually, this might become a more configurable project.

## Taxonomy

An instance of Elightscape controls a single __home__, which may contain multiple __rooms__, each of which has its own set of __lights__.

Moreover, each room has a set of named __scenes__, that is, configurations of lights.
Such scenes always come in two different versions for the different __times of day__: _day_ and _night_.

Each room also has a __controller__, which is responsible for changing the lights according to a given set of __inputs__.
Inputs are, for example: other devices, triggers from Home Assistant.
Each kind of input is handled by an __input driver__, which is given a configuration and is responsible for listening to this input, pre-processing any events and sending them to the appropriate controller.

## Behaviour of Inputs

This section is preliminary.
I am documenting the behaviour as it is currently implemented.

### IKEA Remotes

- Toggle button: the behaviour will vary according to the current (visible) state and the number of clicks
  - When clicked once: if the lights are currently on, they are turned definitively off; if the lights are turned off, they are turned on with a timeout
