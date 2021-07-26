#!/bin/bash

# DigitalOcean Marketplace Image Validation Tool
# © 2021 DigitalOcean LLC.
# This code is licensed under Apache 2.0 license (see LICENSE.md for details)

rm -rvf /etc/nginx/sites-enabled/default

ln -s /etc/nginx/sites-available/digitalocean \
      /etc/nginx/sites-enabled/digitalocean

rm -rf /var/www/html/index*debian.html

chown -R www-data: /var/www