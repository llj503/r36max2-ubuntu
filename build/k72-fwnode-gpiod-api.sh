#!/bin/bash
# k72-fwnode-gpiod-api.sh - the 17 button descriptors come back as an error the
# driver quietly tolerates (-ENOENT/-ENOSYS).  Read what property names
# devm_fwnode_gpiod_get_index() actually looks for, because our child nodes use
# a bare "gpios" property and the vendor spells the rumble supply "rumble-gpio"
# (singular) - which somehow DID work.
set -uo pipefail
K=/root/r36/linux-7.2.8

echo "=== devm_fwnode_gpiod_get_index ==="
grep -n -A45 "^struct gpio_desc \*devm_fwnode_gpiod_get_index" $K/drivers/gpio/gpiod.c | head -70

echo
echo "=== the fwnode lookup helper it calls (gpiod_get_from_properties / fwnode_gpiod_find) ==="
grep -n -B2 -A40 "static struct gpio_desc \*fwnode_get_gpiod_by_index\|gpiod_get_from_properties\|fwnode_gpiod_index" $K/drivers/gpio/gpiod.c | head -90

echo
echo "=== does the OF layer build '<con_id>-gpios' and fall back to 'gpios'? ==="
grep -n -B4 -A30 "of_get_named_gpiod_flags\|-gpios\"" $K/drivers/gpio/gpiod-of.c 2>/dev/null | head -60
ls $K/drivers/gpio/gpiod*.c | sed 's/^/  /'

echo
echo "=== the suffix rule ==="
grep -rn "gpio-ranges\|\"-gpios\"\|-gpios\b" $K/drivers/gpio/gpiod.c | head -12
