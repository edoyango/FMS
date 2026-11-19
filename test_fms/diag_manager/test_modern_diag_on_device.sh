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
# the host, for the modern (yaml) diag_manager, and that unmasked time-average data containing the
# missing value fail in both paths, for time means, maxima, minima and instantaneous values. Some of the
# fields are only on the host, so that send_data has to copy them to the device. Without an OpenMP device
# both runs use the host. It also checks that on_device is ignored when OpenMP target regions run on the host
# (OMP_TARGET_OFFLOAD=disabled).

# Set common test settings.
. ../test-lib.sh

if [ -z "${parser_skip}" ]; then
output_dir

# Block style only: the FMS yaml parser does not handle flow mappings ({...}).
cat <<_EOF > diag_table.yaml
title: test_modern_diag_on_device
base_date: 2 1 1 0 0 0
diag_files:
- file_name: dev_mean
  time_units: hours
  unlimdim: time
  freq: 6 hours
  varlist:
  - module: test_mod
    var_name: t3
    reduction: average
    kind: r4
  - module: test_mod
    var_name: u3
    reduction: average
    kind: r4
  - module: test_mod
    var_name: t2
    reduction: average
    kind: r8
  - module: test_mod
    var_name: u2
    reduction: average
    kind: r4
  - module: test_mod
    var_name: f4
    reduction: average
    kind: r4
  - module: test_mod
    var_name: static
    reduction: none
    kind: r4
  - module: test_mod
    var_name: h3
    reduction: average
    kind: r8
  - module: test_mod
    var_name: h2
    reduction: average
    kind: r8
  - module: test_mod
    var_name: l3
    reduction: average
    kind: r8
  - module: test_mod
    var_name: l2
    reduction: average
    kind: r8
- file_name: dev_inst
  time_units: hours
  unlimdim: time
  freq: 6 hours
  varlist:
  - module: test_mod
    var_name: t3
    reduction: none
    kind: r8
  - module: test_mod
    var_name: u3
    reduction: none
    kind: r4
  - module: test_mod
    var_name: t2
    reduction: none
    kind: r4
  - module: test_mod
    var_name: f4
    reduction: none
    kind: r4
  - module: test_mod
    var_name: h3
    reduction: none
    kind: r8
  - module: test_mod
    var_name: l2
    reduction: none
    kind: r8
- file_name: dev_max
  time_units: hours
  unlimdim: time
  freq: 6 hours
  varlist:
  - module: test_mod
    var_name: t3
    reduction: max
    kind: r8
  - module: test_mod
    var_name: u3
    reduction: max
    kind: r4
  - module: test_mod
    var_name: t2
    reduction: max
    kind: r8
  - module: test_mod
    var_name: f4
    reduction: max
    kind: r4
  - module: test_mod
    var_name: h3
    reduction: max
    kind: r8
  - module: test_mod
    var_name: h2
    reduction: max
    kind: r8
  - module: test_mod
    var_name: l3
    reduction: max
    kind: r8
  - module: test_mod
    var_name: l2
    reduction: max
    kind: r8
- file_name: dev_min
  time_units: hours
  unlimdim: time
  freq: 6 hours
  varlist:
  - module: test_mod
    var_name: t3
    reduction: min
    kind: r8
  - module: test_mod
    var_name: u2
    reduction: min
    kind: r4
  - module: test_mod
    var_name: t2
    reduction: min
    kind: r4
  - module: test_mod
    var_name: f4
    reduction: min
    kind: r4
  - module: test_mod
    var_name: h3
    reduction: min
    kind: r8
  - module: test_mod
    var_name: h2
    reduction: min
    kind: r8
  - module: test_mod
    var_name: l3
    reduction: min
    kind: r8
  - module: test_mod
    var_name: l2
    reduction: min
    kind: r8
_EOF

for mode in host device host_miss device_miss host_nodev device_nodev; do
  rm -rf $mode ; mkdir $mode
  cp diag_table.yaml $mode/
  case $mode in device*) dev=.true. ;; *) dev=.false. ;; esac
  case $mode in *_miss) miss=.true. ;; *) miss=.false. ;; esac
  printf "&test_diag_on_device_nml\n on_device = $dev\n f4_missing = .false.\n u2_missing = $miss\n/\n" > $mode/input.nml
  printf "&diag_manager_nml\n use_modern_diag = .true.\n/\n" >> $mode/input.nml
done

test_expect_success "modern send_data from the host" '
  (cd host && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "modern send_data from the device" '
  (cd device && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "modern device and host output are identical" '
  n=0
  for f in host/dev_*.nc*; do
    cmp $f device/$(basename $f) || exit 1
    n=$((n+1))
  done
  test $n -ge 4
'
test_expect_failure "modern host post of unmasked data with a missing value" '
  (cd host_miss && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_failure "modern device post of unmasked data with a missing value" '
  (cd device_miss && mpirun -n 1 ../../test_diag_on_device)
'

export OMP_TARGET_OFFLOAD=disabled
test_expect_success "modern send_data from the host, target regions on the host" '
  (cd host_nodev && mpirun -n 1 ../../test_diag_on_device)
'
test_expect_success "modern send_data with on_device, target regions on the host" '
  (cd device_nodev && mpirun -n 1 ../../test_diag_on_device)
'
unset OMP_TARGET_OFFLOAD
test_expect_success "modern output with on_device ignored is identical to host output" '
  n=0
  for f in host_nodev/dev_*.nc*; do
    cmp $f device_nodev/$(basename $f) || exit 1
    n=$((n+1))
  done
  test $n -ge 4
'
fi
test_done
