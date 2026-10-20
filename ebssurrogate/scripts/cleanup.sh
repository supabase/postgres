#!/bin/bash

# DigitalOcean Marketplace Image Validation Tool
# © 2021 DigitalOcean LLC.
# This code is licensed under Apache 2.0 license (see LICENSE.md for details)

set -ex

# shellcheck source=/dev/null
source /tmp/provision-common.sh

# Ensure /tmp exists and has the proper permissions before
# checking for security updates
# https://github.com/digitalocean/marketplace-partners/issues/94
ensure_tmp_dir

purge_packages

scrub_history
scrub_logs_and_keys

# Securely erase the unused portion of the filesystem
cat <<-EOF
	Writing zeros to the remaining disk space to securely erase the unused portion of the file system.
	Depending on your disk size this may take several minutes.
	The secure erase will complete successfully when you see:
	    dd: writing to '/zerofile': No space left on device
	Beginning secure erase now
EOF

zero_free_space
empty_login_records
