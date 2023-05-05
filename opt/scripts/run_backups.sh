#!/bin/bash
echo "Running borg foo backup"
systemctl start borg@foo
echo "Running borg foo offsite backup"
systemctl start borg@foo-offsite
echo "Running borg foo rsync backup"
systemctl start borg@foo-rsync
echo "Running borg bar backup"
systemctl start borg@bar