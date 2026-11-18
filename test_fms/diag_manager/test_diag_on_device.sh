#!/bin/sh

#***********************************************************************
#*                             Apache License 2.0
#*
#* This file is part of the GFDL Flexible Modeling System (FMS).
#*
#* Licensed under the Apache License, Version 2.0 (the "License");
#* you may not use this file except in compliance with the License.
#* You may obtain a copy of the License at
#*
#*     http://www.apache.org/licenses/LICENSE-2.0
#*
#* FMS is distributed in the hope that it will be useful, but WITHOUT
#* WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied;
#* without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
#* PARTICULAR PURPOSE. See the License for the specific language
#* governing permissions and limitations under the License.
#***********************************************************************

# Checks that send_data with on_device=.true. gives the same output as posting the same data from
# the host, for the old diag_manager, for time means, maxima, minima and instantaneous values. Some of the
# fields are only on the host, so that send_data has to copy them to the device. Without an OpenMP device both
# runs use the host. It also checks that on_device is ignored when OpenMP target regions run on the host
# (OMP_TARGET_OFFLOAD=disabled).

# Set common test settings.
. ../test-lib.sh

output_dir

cat <<_EOF > diag_table
test_diag_on_device
2 1 1 0 0 0
"dev_mean", 6, "hours", 1, "hours", "time"
"dev_inst", 6, "hours", 1, "hours", "time"
"dev_max", 6, "hours", 1, "hours", "time"
"dev_min", 6, "hours", 1, "hours", "time"
"test_mod", "t3", "t3", "dev_mean", "all", .true., "none", 2
"test_mod", "u3", "u3", "dev_mean", "all", .true., "none", 2
"test_mod", "t2", "t2", "dev_mean", "all", .true., "none", 2
"test_mod", "u2", "u2", "dev_mean", "all", .true., "none", 2
"test_mod", "f4", "f4", "dev_mean", "all", .true., "none", 2
"test_mod", "static", "static", "dev_mean", "all", .false., "none", 2
"test_mod", "h3", "h3", "dev_mean", "all", .true., "none", 2
"test_mod", "h2", "h2", "dev_mean", "all", .true., "none", 2
"test_mod", "l3", "l3", "dev_mean", "all", .true., "none", 2
"test_mod", "l2", "l2", "dev_mean", "all", .true., "none", 2
"test_mod", "t3", "t3", "dev_inst", "all", .false., "none", 2
"test_mod", "u3", "u3", "dev_inst", "all", .false., "none", 2
"test_mod", "t2", "t2", "dev_inst", "all", .false., "none", 2
"test_mod", "f4", "f4", "dev_inst", "all", .false., "none", 2
"test_mod", "h3", "h3", "dev_inst", "all", .false., "none", 2
"test_mod", "l2", "l2", "dev_inst", "all", .false., "none", 2
"test_mod", "t3", "t3", "dev_max", "all", "max", "none", 2
"test_mod", "u3", "u3", "dev_max", "all", "max", "none", 2
"test_mod", "t2", "t2", "dev_max", "all", "max", "none", 2
"test_mod", "f4", "f4", "dev_max", "all", "max", "none", 2
"test_mod", "h3", "h3", "dev_max", "all", "max", "none", 2
"test_mod", "h2", "h2", "dev_max", "all", "max", "none", 2
"test_mod", "l3", "l3", "dev_max", "all", "max", "none", 2
"test_mod", "l2", "l2", "dev_max", "all", "max", "none", 2
"test_mod", "t3", "t3", "dev_min", "all", "min", "none", 2
"test_mod", "u2", "u2", "dev_min", "all", "min", "none", 2
"test_mod", "t2", "t2", "dev_min", "all", "min", "none", 2
"test_mod", "f4", "f4", "dev_min", "all", "min", "none", 2
"test_mod", "h3", "h3", "dev_min", "all", "min", "none", 2
"test_mod", "h2", "h2", "dev_min", "all", "min", "none", 2
"test_mod", "l3", "l3", "dev_min", "all", "min", "none", 2
"test_mod", "l2", "l2", "dev_min", "all", "min", "none", 2
_EOF

for mode in host device host_nodev device_nodev; do
  rm -rf $mode ; mkdir $mode
  cp diag_table $mode/
  case $mode in device*) dev=.true. ;; *) dev=.false. ;; esac
  printf "&test_diag_on_device_nml\n on_device = $dev\n/\n" > $mode/input.nml
done

test_expect_success "send_data from the host" '
  (cd host && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "send_data from the device" '
  (cd device && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "device and host output are identical" '
  n=0
  for f in host/dev_*.nc*; do
    cmp $f device/$(basename $f) || exit 1
    n=$((n+1))
  done
  test $n -ge 4
'

export OMP_TARGET_OFFLOAD=disabled
test_expect_success "send_data from the host, target regions on the host" '
  (cd host_nodev && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "send_data with on_device, target regions on the host" '
  (cd device_nodev && mpirun -n 1 ../../test_diag_on_device)
'
unset OMP_TARGET_OFFLOAD
test_expect_success "output with on_device ignored is identical to host output" '
  n=0
  for f in host_nodev/dev_*.nc*; do
    cmp $f device_nodev/$(basename $f) || exit 1
    n=$((n+1))
  done
  test $n -ge 4
'
test_done
