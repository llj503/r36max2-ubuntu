#!/bin/bash
# k72-fwnode-gpiod-api2.sh - the core lives in gpiolib.c / gpiolib-of.c in 7.2.
# Find out exactly which DT property names devm_fwnode_gpiod_get_index(dev,
# child_fwnode, "gpios", 0, ...) will look for, and what it returns when the
# child only has a bare "gpios" property.
set -uo pipefail
K=/root/r36/linux-7.2.8/drivers/gpio

echo "=== files ==="
ls $K/gpiolib*.c | sed 's/^/  /'

echo
echo "=== devm_fwnode_gpiod_get_index ==="
grep -n -A40 "^struct gpio_desc \*devm_fwnode_gpiod_get_index" $K/gpiolib.c | head -60

echo
echo "=== fwnode_gpiod_get_index / the property-name building ==="
grep -n -B4 -A45 "static struct gpio_desc \*fwnode_gpiod_get_index" $K/gpiolib.c | head -80

echo
echo "=== the OF side: which suffixes it tries ==="
grep -n -B6 -A34 "of_get_gpiod_by_index\|of_property_get_reference_args\|-gpios" $K/gpiolib-of.c | head -90
