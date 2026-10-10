#!/bin/bash
# Listed by EmulationStation as an entry in the "Ports" system (es_systems.cfg points
# /roms/ports at .sh files), and it is what a user picks to open PortMaster and
# download ports.  It is a one-line forwarder on purpose: the seeding, the PATH and
# the controlfolder checks all live in r36-portmaster, so there is one place to fix.
exec /usr/local/bin/r36-portmaster
